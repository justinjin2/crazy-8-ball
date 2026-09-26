--!strict
-- Match-only presentation. Every deadline and outcome comes from the server snapshot.
-- Built from the UI kit (HudParts, docs/UI_STYLE.md):
-- - the top bar, like the reference match bar on white: a card per team (portraits and the
--   numbered balls) and the status card (a phase icon, what is happening, the clock, Leave);
-- - the foul popup, with no panel;
-- - the ball-in-hand hint and the wrong-target warning;
-- - the leave and surrender dialog;
-- - the coin flip and result cards.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local HudParts = require(script.Parent.HudParts)
local UIAnim = require(script.Parent.UIAnim)
local Copy = Strings.Match
local S = Config.Multiplayer.Style
local K = Config.UI.Kit
local MatchHUD = {}
MatchHUD.__index = MatchHUD

local tone = HudParts.tone
local frame = HudParts.frame
local corner = HudParts.corner
local text = HudParts.text
local candy = HudParts.candy

local function nameFor(snapshot: any, userId: number?): string
	for _, seat in snapshot.seats do
		if seat.userId == userId then
			return seat.displayName or seat.name
		end
	end
	return Copy.Opponent
end

local function localTeam(snapshot: any, userId: number): number
	for _, seat in snapshot.seats do
		if seat.userId == userId then
			return seat.team
		end
	end
	return 1
end

local function pocketed(snapshot: any, id: number): boolean
	local ball = snapshot.balls and snapshot.balls[id + 1]
	if type(ball) == "table" then
		return ball.pocketed == true
	end
	-- Packed wire states use {x, y, z, pocketed} for each ascending ball ID.
	return snapshot.balls ~= nil and snapshot.balls[id * 4 + 4] == 1
end

local function eligible(snapshot: any, team: number): boolean
	local group = snapshot.groups and snapshot.groups[team]
	if group == nil then
		return false
	end
	-- Solo clears both groups before the 8. Checked on the balls, not the group, because
	-- the replay that clears the first group still shows that group as the player's.
	local starts: { number } = if snapshot.solo
		then { 1, 9 }
		else { if group == "solids" then 1 else 9 }
	for _, start in starts do
		for id = start, start + 6 do
			if not pocketed(snapshot, id) then
				return false
			end
		end
	end
	return true
end

-- The icon beside the status: what is happening now, and whether it is up to you.
local function phaseIcon(snapshot: any, isShooter: boolean, ours: number): string
	local phase = snapshot.phase
	if phase == "Foul" then
		return "Whistle"
	elseif phase == "Resolving" then
		return "Rolling"
	elseif phase == "CoinFlip" then
		return "Coin"
	elseif phase == "Result" then
		local result = snapshot.result
		if not result or not result.winner then
			return "Flag"
		end
		return if result.winner == ours then "Trophy" else "Sad"
	elseif not isShooter then
		return "Hourglass"
	elseif phase == "Placement" then
		return "Hand"
	elseif phase == "PocketChoice" then
		return "Target"
	end
	return "Cue"
end

-- A picture and one line side by side, centred: the hint pill and the wrong-target warning.
local function iconLine(
	parent: Instance,
	name: string,
	iconKey: string,
	size: number,
	tint: Color3?
): any
	local root = frame(parent, name)
	local icon = HudParts.icon(root, iconKey)
	local words = text(root, "Text", size, "", tint)
	return { root = root, icon = icon, text = words, size = size }
end

local function layoutIconLine(line: any, height: number)
	local iconSize = math.floor(height * 0.8)
	line.icon.AnchorPoint = Vector2.new(0, 0.5)
	line.icon.Position = UDim2.new(0, math.floor(height * 0.25), 0.5, 0)
	line.icon.Size = UDim2.fromOffset(iconSize, iconSize)
	local left = math.floor(height * 0.25) + iconSize + 6
	line.text.Position = UDim2.fromOffset(left, 2)
	line.text.Size = UDim2.new(1, -left - math.floor(height * 0.3), 1, -4)
end

local function makePortrait(parent: Instance): any
	local root = frame(parent, "Player")
	local imageFrame = HudParts.card(root, "PortraitFrame", S.PortraitCornerPx)
	local fill = imageFrame:FindFirstChild("Fill") :: Frame
	local border = fill:FindFirstChild("Edge") :: UIStroke
	local fallback = text(imageFrame, "Fallback", K.Text.Heading, Copy.AvatarFallback)
	fallback.Size = UDim2.fromScale(1, 1)
	local avatar = Instance.new("ImageLabel")
	avatar.Name = "Avatar"
	avatar.BackgroundTransparency = 1
	avatar.ScaleType = Enum.ScaleType.Fit
	avatar.Position = UDim2.fromOffset(2, 2)
	avatar.Size = UDim2.new(1, -4, 1, -4)
	avatar.Parent = imageFrame
	corner(avatar, S.PortraitCornerPx - 2)
	-- No name under the portrait (designer, 2026-09-26; a rank badge goes there later). A player
	-- who has left gets a red X over a faded picture.
	local gone = HudParts.icon(imageFrame, "X", "Left")
	gone.AnchorPoint = Vector2.new(0.5, 0.5)
	gone.Position = UDim2.fromScale(0.5, 0.5)
	gone.Size = UDim2.fromScale(0.7, 0.7)
	gone.ZIndex = 5
	gone.Visible = false
	local active = frame(imageFrame, "ActiveMarker")
	active.AnchorPoint = Vector2.new(0.5, 0.5)
	active.Position = UDim2.new(1, -2, 1, -2)
	active.Size = UDim2.fromOffset(S.ActiveDotPx, S.ActiveDotPx)
	active.BackgroundTransparency = 0
	active.BackgroundColor3 = tone("Green")
	active.ZIndex = 4
	corner(active, S.ActiveDotPx)
	local dotEdge = Instance.new("UIStroke")
	dotEdge.Color = tone("Ink")
	dotEdge.Thickness = 2.5
	dotEdge.Parent = active
	-- The shot clock runs round the portrait of whoever is shooting, draining as it runs.
	local perimeter = {}
	for i = 1, 4 do
		local edge = frame(imageFrame, "ClockEdge" .. i)
		edge.BackgroundTransparency = 0
		edge.BackgroundColor3 = tone("Green")
		edge.ZIndex = 3
		table.insert(perimeter, edge)
	end
	return {
		root = root,
		imageFrame = imageFrame,
		image = avatar,
		fallback = fallback,
		gone = gone,
		active = active,
		border = border,
		edges = perimeter,
		userId = nil,
		occupied = false,
	}
end

-- The OPEN TABLE label over a team's ball area, with the balls already down beside it.
local function layoutOpen(
	team: any,
	ballLeft: number,
	ballTop: number,
	ballsWidth: number,
	rowsHeight: number,
	ballRows: number,
	sizes: any
)
	team.open.Position = UDim2.fromOffset(ballLeft, ballTop)
	team.open.Size = UDim2.fromOffset(ballsWidth, rowsHeight)
	HudParts.setTextSize(team.open, sizes.status)
	team.open.TextXAlignment = Enum.TextXAlignment.Center
	if team.openCount > 0 then
		-- The label moves aside (one row) or up (two rows) to make room for the balls.
		local labelWidth, rowLeft, rowTop, rowWidth, size
		if ballRows == 1 then
			labelWidth = math.floor(ballsWidth * S.OpenLabelShare)
			rowLeft, rowTop, rowWidth = ballLeft + labelWidth, ballTop, ballsWidth - labelWidth
			size = S.OpenBallSize
		else
			labelWidth = ballsWidth
			rowLeft, rowTop, rowWidth = ballLeft, ballTop + rowsHeight / 2, ballsWidth
			size = S.ShortOpenBallSize
		end
		local miniGap = S.BallGap / 2
		size = math.max(
			S.OpenBallMinSize,
			math.min(size, math.floor((rowWidth + miniGap) / team.openCount) - miniGap)
		)
		HudParts.setTextSize(team.open, S.NameSize)
		team.open.TextXAlignment = if ballRows == 1
			then Enum.TextXAlignment.Left
			else Enum.TextXAlignment.Center
		team.open.Size =
			UDim2.fromOffset(labelWidth, if ballRows == 1 then rowsHeight else rowsHeight / 2)
		team.openRow.Position = UDim2.fromOffset(rowLeft, rowTop)
		team.openRow.Size =
			UDim2.fromOffset(rowWidth, if ballRows == 1 then rowsHeight else rowsHeight / 2)
		local rowHeight = if ballRows == 1 then rowsHeight else rowsHeight / 2
		local n = 0
		for _, ball in team.openBalls do
			if ball.down then
				ball.root.Position = UDim2.fromOffset(n * (size + miniGap), (rowHeight - size) / 2)
				HudParts.sizeBall(ball, size)
				n += 1
			end
		end
	end
end

-- The top bar's sizes: full, or compact on short screens (a phone on its side) so a 3v3 still
-- fits on one line and the table keeps most of the screen.
local function barSizes(short: boolean): any
	return {
		portrait = if short then S.ShortPortraitSize else S.PortraitSize,
		header = if short then S.ShortHeaderHeight else S.HeaderHeight,
		center = if short then S.ShortCenterWidth else S.HeaderCenterWidth,
		status = if short then S.ShortStatusSize else S.StatusSize,
		leave = if short then S.ShortLeaveSize else S.LeaveSize,
		clockWidth = if short then S.ShortClockPillWidth else S.ClockPillWidth,
		clockHeight = if short then S.ShortClockPillHeight else S.ClockPillHeight,
		clockText = if short then S.ShortClockTextSize else S.ClockTextSize,
		gap = if short then S.ShortHeaderGap else S.HeaderGap, -- a phone packs a little tighter
		ball = if short then S.ShortBallSize else S.BallSize,
	}
end

local function makeTeam(parent: Instance, name: string): any
	local root = HudParts.card(parent, name)
	local portraits, balls = {}, {}
	for _ = 1, 3 do
		table.insert(portraits, makePortrait(root))
	end
	for _ = 1, 8 do
		table.insert(balls, HudParts.ball(root))
	end
	local open = HudParts.note(root, "OpenTable", S.StatusSize, Copy.OpenTable)
	-- While the table is open nobody owns a group yet, but balls can already be down (the
	-- break). They show here, small and crossed out in their own colours, until the groups
	-- are decided. The 8 is left out: on the break it is always re-spotted.
	local openRow = frame(root, "OpenPocketed")
	local openBalls = {}
	for id = 1, 15 do
		if id ~= 8 then
			local ball = HudParts.ball(openRow)
			ball.id = id
			table.insert(openBalls, ball)
		end
	end
	return {
		root = root,
		portraits = portraits,
		balls = balls,
		open = open,
		openRow = openRow,
		openBalls = openBalls,
		openCount = 0,
	}
end

function MatchHUD.new(screen: ScreenGui, onAction: (string, any?) -> ()): any
	local self: any = setmetatable({}, MatchHUD)
	self.onAction = onAction
	self.snapshot = nil
	-- No LocalPlayer only in an Edit-mode preview of the screens.
	self.localUserId = if Players.LocalPlayer then Players.LocalPlayer.UserId else 0
	self.lastNow = workspace:GetServerTimeNow()
	self.connections = {}
	self.alive = true
	-- Ball in hand, from Main: whether the local shooter may move the cue ball now, and
	-- whether it just failed to follow the pointer.
	self.placing = false
	self.placingBlocked = false
	self.invalidTarget = false
	self.modalMode = nil
	self.respondedVote = nil
	self.width = 0
	self.avatarCache = {}
	self.shoneTurn = nil -- the turn whose "your turn" shine has played
	self.shoneResult = nil -- the result whose shine has played
	-- Which balls were down in the last snapshot, by id, so a ball pops when IT goes down
	-- rather than when a slot's contents change (the rows remap when colors are revealed).
	self.downIds = {}
	self.root = frame(screen, "MultiplayerHUD")
	self.root.ZIndex = 2 -- setup targets are a lower sibling; dialogs always cover them
	self.root.Size = UDim2.fromScale(1, 1)
	self.root.Visible = false
	-- The free part of Roblox's own top bar (right of its menu, chat and voice buttons): a
	-- ScreenGui with TopbarSafeInsets covers exactly that, on every device. The top bar sits
	-- there when it fits, so a phone keeps the table in view (designer, 2026-09-26).
	local probe = Instance.new("ScreenGui")
	probe.Name = "TopbarRoom"
	probe.ScreenInsets = Enum.ScreenInsets.TopbarSafeInsets
	probe.ResetOnSpawn = false
	-- Only a real PlayerGui has Roblox's top bar (an Edit-mode preview uses the fallbacks).
	probe.Parent = if Players.LocalPlayer
		then Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
		else nil
	self.topbarRoom = frame(probe, "Area")
	self.topbarRoom.Size = UDim2.fromScale(1, 1)
	table.insert(
		self.connections,
		self.topbarRoom:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			self:layout()
		end)
	)
	self.teams = { makeTeam(self.root, "LocalTeam"), makeTeam(self.root, "OtherTeam") }
	-- Solo: fifteen slots on the local panel in playing order (first group, other group, 8).
	self.teams[1].soloBalls, self.teams[2].soloBalls = {}, {}
	for _ = 1, 15 do
		table.insert(self.teams[1].soloBalls, HudParts.ball(self.teams[1].root))
	end

	-- The status card: a phase icon, the status and detail lines, the clock and Leave.
	self.center = HudParts.card(self.root, "MatchStatus")
	self.centerFill = self.center:FindFirstChild("Fill")
	self.phaseIcon = HudParts.icon(self.center, "Cue", "PhaseIcon")
	-- One line: whose turn it is, or what is happening (designer, 2026-09-26).
	self.status = text(self.center, "Status", S.StatusSize, "")
	self.status.TextXAlignment = Enum.TextXAlignment.Left
	self.status.TextWrapped = false
	self.clockPill = HudParts.pill(self.center, "Clock")
	self.clockScale = Instance.new("UIScale")
	self.clockScale.Parent = self.clockPill
	self.clockIcon = HudParts.icon(self.clockPill, "Stopwatch")
	self.clock = text(self.clockPill, "Timer", S.ClockTextSize, "")
	-- A small red door: Leave, without taking the status's room.
	self.leave = candy(self.center, "", function()
		self:openLeave()
	end, "Red", "Door")
	HudParts.setMinHit(self.leave, S.TouchTargetPx)

	-- One line of instruction while the cue ball is in hand. There is nothing to confirm:
	-- the ball stays where it is left, and the shot can be taken at any time.
	self.setup = HudParts.pill(self.root, "Setup")
	self.setup.AnchorPoint = Vector2.new(0.5, 1)
	self.setupLine = iconLine(self.setup, "Hint", "Hand", S.StatusSize)
	self.setupLine.root.Size = UDim2.fromScale(1, 1)
	self.setupLabel = self.setupLine.text
	self.setupLabel.TextWrapped = false -- one line: it shrinks to fit rather than wrapping

	-- The foul popup: FOUL! and the rule that was broken in a few words. No panel, so it
	-- hides little of the table; it never takes input (the next shooter can already place and
	-- aim underneath it). Drawn from the server clock, so everyone sees it together.
	self.foulGroup = frame(self.root, "FoulPopup")
	self.foulGroup.AnchorPoint = Vector2.new(0.5, 0)
	self.foulGroup.Visible = false
	self.foulScale = Instance.new("UIScale")
	self.foulScale.Parent = self.foulGroup
	self.foulIcon = HudParts.icon(self.foulGroup, "Whistle")
	self.foulTitle = text(self.foulGroup, "Title", S.FoulTitleSize, Copy.FoulPopup, tone("Red"))
	self.foulTitle.TextWrapped = false
	self.foulReason = text(self.foulGroup, "Reason", S.FoulReasonSize, "")
	self.foulKey = ""
	self.foulUntil = 0
	self.foulStart = 0

	self.invalidLine = iconLine(self.root, "InvalidTarget", "X", S.StatusSize, tone("Red"))
	self.invalid = self.invalidLine.root
	self.invalid.AnchorPoint = Vector2.new(0.5, 1)
	self.invalidLine.text.Text = Copy.InvalidTarget
	self.invalidLine.text.TextWrapped = false

	-- The leave / surrender question, over a dimmed screen.
	self.modal = Instance.new("TextButton")
	self.modal.Name = "ConfirmationBackdrop"
	self.modal.Size = UDim2.fromScale(1, 1)
	self.modal.BackgroundColor3 = tone("Ink")
	self.modal.BackgroundTransparency = 1 - S.ModalDim
	self.modal.AutoButtonColor = false
	self.modal.Text = ""
	self.modal.Active = true
	self.modal.Modal = true
	self.modal.Selectable = false
	self.modal.Visible = false
	self.modal.ZIndex = 20
	self.modal.Parent = self.root
	self.dialog = HudParts.card(self.modal, "Dialog")
	self.modalTweens = {}
	self.dialog.AnchorPoint = Vector2.new(0.5, 0.5)
	self.dialog.Position = UDim2.fromScale(0.5, 0.5)
	self.dialogIcon = HudParts.icon(self.dialog, "Door", "DialogIcon")
	self.dialogTitle = text(self.dialog, "Title", K.Text.Heading, "")
	self.dialogBody = HudParts.note(self.dialog, "Explanation", K.Text.Body, "")
	self.voteProgress = text(self.dialog, "VoteStatus", K.Text.Body, "", tone("Green"))
	self.yes = candy(self.dialog, Copy.Yes, function()
		local mode = self.modalMode
		self:closeModal()
		if mode == "Vote" then
			self.respondedVote = self:voteKey()
			onAction("Vote", true)
		else
			onAction("Surrender", nil)
		end
	end, "Red")
	self.no = candy(self.dialog, Copy.No, function()
		local mode = self.modalMode
		self:closeModal()
		if mode == "Vote" then
			self.respondedVote = self:voteKey()
			onAction("Vote", false)
		end
	end, "Blue")

	-- The coin flip and the result: a card over a dimmed screen, faded as one.
	self.overlay = Instance.new("CanvasGroup")
	self.overlay.Name = "MatchPresentation"
	self.overlay.Size = UDim2.fromScale(1, 1)
	self.overlay.BackgroundColor3 = tone("Ink")
	self.overlay.BackgroundTransparency = 1 - S.ModalDim
	self.overlay.ZIndex = 10
	self.overlay.Visible = false
	self.overlay.Parent = self.root
	-- The rays turn behind the card, round the result icon that sits on its top edge.
	self.rays = Instance.new("ImageLabel")
	self.rays.Name = "Rays"
	self.rays.BackgroundTransparency = 1
	self.rays.Image = K.Art.Rays
	self.rays.ImageColor3 = tone("Gold")
	self.rays.AnchorPoint = Vector2.new(0.5, 0.5)
	self.rays.ZIndex = 1
	self.rays.Parent = self.overlay
	self.presentation = HudParts.card(self.overlay, "Presentation")
	self.presentation.ZIndex = 2
	self.presentationFill = self.presentation:FindFirstChild("Fill")
	self.presentationScale = Instance.new("UIScale")
	self.presentationScale.Parent = self.presentation
	self.presentation.AnchorPoint = Vector2.new(0.5, 0.5)
	self.presentation.Position = UDim2.fromScale(0.5, 0.5)
	self.resultIcon = HudParts.icon(self.presentation, "Trophy", "ResultIcon")
	self.resultIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	self.resultIcon.ZIndex = 3
	self.presentationTitle = text(self.presentation, "Heading", K.Text.Title, "")
	self.presentationText = HudParts.note(self.presentation, "Explanation", K.Text.Body, "")
	self.coin = frame(self.presentation, "Coin")
	self.coin.AnchorPoint = Vector2.new(0.5, 0.5)
	local coinFace = HudParts.icon(self.coin, "Coin", "Face")
	coinFace.ScaleType = Enum.ScaleType.Stretch
	coinFace.Size = UDim2.fromScale(1, 1)
	self.coinGlyph = text(self.coin, "Glyph", K.Text.Title, Copy.CoinHeadGlyph, tone("Gold"))
	self.coinGlyph.Size = UDim2.fromScale(1, 1)
	self.coinGlyph.ZIndex = 2
	self.coinOwner = HudParts.note(self.presentation, "Sides", S.NameSize, "")
	table.insert(
		self.connections,
		self.root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			self:layout()
		end)
	)
	self:layout()
	return self
end

function MatchHUD.layout(self: any)
	local width = self.root.AbsoluteSize.X
	if width <= 0 then
		return
	end
	self.width = width
	local short = self.root.AbsoluteSize.Y < S.ShortHeight
	local d = barSizes(short)
	self.bar = d
	local margin, gap = S.HeaderMargin, d.gap
	local count = if self.snapshot then self.snapshot.teamSize else 3
	local portraitSize = d.portrait
	local portraitsWidth = portraitSize * count + S.PortraitGap * (count - 1)
	local availableWidth = width - margin * 2
	local menuLeft, menuRight = self:menuRoom(width)
	local besideRoom = math.min(width - menuLeft - menuRight, availableWidth)
	-- The first arrangement that fits, beside Roblox's buttons or under them: one row of eight
	-- balls a side, or two rows of four. A phone would rather have two rows beside the buttons
	-- (the table keeps the screen); a computer would rather have one row of bigger balls.
	-- Failing both, the teams sit over the status card.
	local function widthFor(columns: number, size: number, center: number): number
		local balls = size * columns + S.BallGap * (columns - 1)
		return (portraitsWidth + balls + gap * 3) * 2 + center + gap * 2
	end
	local oneRowBeside = { columns = 8, size = d.ball, beside = true }
	local oneRowUnder = { columns = 8, size = d.ball, beside = false }
	local twoRowsBeside = { columns = 4, size = S.ShortBallSize, beside = true }
	local twoRowsUnder = { columns = 4, size = S.ShortBallSize, beside = false }
	local order: { any } = if short
		then { oneRowBeside, twoRowsBeside, oneRowUnder, twoRowsUnder }
		else { oneRowBeside, oneRowUnder, twoRowsBeside, twoRowsUnder }
	local columns, ballSize, besideMenu = 4, S.ShortBallSize, false
	for _, option in order do
		local room = if option.beside then besideRoom else availableWidth
		if widthFor(option.columns, option.size, d.center) <= room then
			columns, ballSize, besideMenu = option.columns, option.size, option.beside
			break
		end
	end
	local ballsWidth = ballSize * columns + S.BallGap * (columns - 1)
	local desiredTeamWidth = portraitsWidth + ballsWidth + gap * 3
	-- On a short screen the status card takes what room is left, up to ShortCenterMax, so
	-- its words fit beside Leave.
	local room = if besideMenu then besideRoom else availableWidth
	local centerWidth = if short
		then math.clamp(room - desiredTeamWidth * 2 - gap * 2, d.center, S.ShortCenterMax)
		else d.center
	d.center = centerWidth
	local desiredWidth = desiredTeamWidth * 2 + centerWidth + gap * 2
	local inline = desiredWidth <= availableWidth
	local teamWidth = if inline then desiredTeamWidth else (availableWidth - gap) / 2
	local ballRows = 8 / columns
	local headerHeight = if inline
		then math.max(d.header, ballSize * ballRows + S.BallGap * (ballRows - 1) + gap * 2)
		else portraitSize + gap * 3 + ballSize * ballRows + S.BallGap * (ballRows - 1)
	besideMenu = besideMenu and inline
	local top = S.HeaderTop - (if besideMenu then GuiService:GetGuiInset().Y else 0)
	local startX = if besideMenu
		then menuLeft + (besideRoom - desiredWidth) / 2
		else (width - (if inline then desiredWidth else availableWidth)) / 2
	self.headerBottom = top + headerHeight + (if inline then 0 else d.header + gap)
	for i, team in self.teams do
		local x = startX
			+ (if i == 1 then 0 else teamWidth + gap + (if inline then centerWidth + gap else 0))
		team.root.Position = UDim2.fromOffset(x, top)
		team.root.Size = UDim2.fromOffset(teamWidth, headerHeight)
		local portraitLeft = if i == 1 then gap else teamWidth - portraitsWidth - gap
		for n, portrait in team.portraits do
			-- Centred in the card's height beside the balls, or at its top over them.
			portrait.root.Position = UDim2.fromOffset(
				portraitLeft + (n - 1) * (portraitSize + S.PortraitGap),
				if inline then (headerHeight - portraitSize) / 2 else gap
			)
			portrait.root.Size = UDim2.fromOffset(portraitSize, portraitSize)
			portrait.imageFrame.Size = UDim2.fromOffset(portraitSize, portraitSize)
			portrait.root.Visible = n <= count and portrait.occupied
		end
		local ballLeft = if inline
			then (if i == 1 then portraitsWidth + gap * 2 else gap)
			else (teamWidth - ballsWidth) / 2
		local ballTop = if inline
			then (headerHeight - ballSize * ballRows - S.BallGap * (ballRows - 1)) / 2
			else portraitSize + gap * 2
		for n, ball in team.balls do
			local column, row = (n - 1) % columns, math.floor((n - 1) / columns)
			ball.root.Position = UDim2.fromOffset(
				ballLeft + column * (ballSize + S.BallGap),
				ballTop + row * (ballSize + S.BallGap)
			)
			HudParts.sizeBall(ball, ballSize)
		end
		local rowsHeight = ballSize * ballRows + S.BallGap * (ballRows - 1)
		layoutOpen(team, ballLeft, ballTop, ballsWidth, rowsHeight, ballRows, d)
	end
	self.center.Position = UDim2.fromOffset(
		if inline then startX + teamWidth + gap else (width - centerWidth) / 2,
		top + (if inline then 0 else headerHeight + gap)
	)
	self.center.Size = UDim2.fromOffset(centerWidth, d.header)
	if self.snapshot and self.snapshot.solo then
		self:layoutSolo(width)
	end
	self:layoutStatus()
	-- The placement instruction: one line centred at the bottom.
	local setupHeight = if short then S.ShortSetupHeight else S.SetupHeight
	local setupWidth = math.min(S.SetupMaxWidth, width - margin * 2)
	self.setup.Position = UDim2.new(0.5, 0, 1, -margin)
	self.setup.Size = UDim2.fromOffset(setupWidth, setupHeight)
	self.setupHeight = setupHeight
	layoutIconLine(self.setupLine, setupHeight)
	HudParts.setTextSize(self.setupLabel, if short then S.NameSize else S.StatusSize)
	local invalidHeight = S.StatusSize + gap * 2
	self.invalid.Size = UDim2.new(1, -margin * 2, 0, invalidHeight)
	layoutIconLine(self.invalidLine, invalidHeight)
	self.invalidLine.text.TextXAlignment = Enum.TextXAlignment.Left
	-- Centre the warning's icon and words together.
	local wordsWidth =
		math.min(self.invalidLine.text.TextBounds.X, width - margin * 2 - invalidHeight * 2)
	local rowWidth = wordsWidth + invalidHeight * 1.3
	self.invalid.Size = UDim2.fromOffset(rowWidth, invalidHeight)
	-- The dialog: its icon on top, the question, the explanation, the vote, then No and Yes.
	local dialogWidth = math.min(S.ModalWidth, width - margin * 2)
	local iconSize = S.DialogIconSize
	local titleTop = gap + iconSize
	local bodyTop = titleTop + K.Text.Heading + gap * 2
	local bodyHeight = K.Text.Body * 3 + gap
	local voteTop = bodyTop + bodyHeight
	local buttonsTop = voteTop + K.Text.Body + gap * 2
	self.dialog.Size = UDim2.fromOffset(dialogWidth, buttonsTop + S.ButtonHeight + gap * 2)
	self.dialogIcon.AnchorPoint = Vector2.new(0.5, 0)
	self.dialogIcon.Position = UDim2.new(0.5, 0, 0, gap)
	self.dialogIcon.Size = UDim2.fromOffset(iconSize, iconSize)
	self.dialogTitle.Position = UDim2.fromOffset(gap * 2, titleTop)
	self.dialogTitle.Size = UDim2.new(1, -gap * 4, 0, K.Text.Heading + gap)
	self.dialogBody.Position = UDim2.fromOffset(gap * 2, bodyTop)
	self.dialogBody.Size = UDim2.new(1, -gap * 4, 0, bodyHeight)
	self.voteProgress.Position = UDim2.fromOffset(gap * 2, voteTop)
	self.voteProgress.Size = UDim2.new(1, -gap * 4, 0, K.Text.Body + gap)
	self.no.Position = UDim2.fromOffset(gap * 2, buttonsTop)
	self.no.Size = UDim2.new(0.5, -gap * 2.5, 0, S.ButtonHeight)
	self.yes.Position = UDim2.new(0.5, gap / 2, 0, buttonsTop)
	self.yes.Size = self.no.Size
	-- The coin flip and result card.
	local result = self.snapshot and self.snapshot.phase == "Result"
	local cardWidth = math.min(S.ModalWidth, width - margin * 2)
	local cardHeight = if result then S.ResultPanelHeight else S.CoinPanelHeight
	self.presentation.Size = UDim2.fromOffset(cardWidth, cardHeight)
	local resultIconSize = S.ResultIconSize
	self.resultIcon.Position = UDim2.fromScale(0.5, 0)
	self.resultIcon.Size = UDim2.fromOffset(resultIconSize, resultIconSize)
	local center = self.overlay.AbsoluteSize / 2
	self.rays.Position = UDim2.fromOffset(center.X, center.Y - cardHeight / 2)
	self.rays.Size = UDim2.fromOffset(resultIconSize * 3, resultIconSize * 3)
	local titleY = if result then resultIconSize / 2 + gap else gap * 2
	self.presentationTitle.Position = UDim2.fromOffset(gap, titleY)
	self.presentationTitle.Size = UDim2.new(1, -gap * 2, 0, K.Text.Title + gap)
	local coinSize = S.CoinSize
	self.coin.Position = UDim2.new(0.5, 0, 0, titleY + K.Text.Title + gap * 2 + coinSize / 2)
	self.coinOwner.Position = UDim2.new(0, gap, 1, -S.ButtonHeight * 1.9)
	self.coinOwner.Size = UDim2.new(1, -gap * 2, 0, S.NameSize + gap)
	self.presentationText.Position = UDim2.new(0, gap * 2, 1, -S.ButtonHeight * 1.2 - gap)
	self.presentationText.Size = UDim2.new(1, -gap * 4, 0, S.ButtonHeight * 1.2)
end

-- How much of the screen's top edge Roblox's own buttons take, left and right, in the root's
-- pixels (Config fallbacks when Roblox does not say).
function MatchHUD.menuRoom(self: any, width: number): (number, number)
	local room = self.topbarRoom
	local probe = room and room.Parent
	if room and probe and probe.Parent and room.AbsoluteSize.X > 0 then
		local rootLeft = self.root.AbsolutePosition.X
		local left = room.AbsolutePosition.X - rootLeft
		local right = rootLeft + width - (room.AbsolutePosition.X + room.AbsoluteSize.X)
		return math.max(0, left) + S.HeaderGap, math.max(0, right) + S.HeaderGap
	end
	return S.HeaderMenuLeft, S.HeaderMenuRight
end

-- Inside the status card: the phase icon on the left, the one-line status, the clock and a
-- small Leave on the right.
function MatchHUD.layoutStatus(self: any)
	local d = self.bar
	local width, height = d.center, d.header
	local pad = d.gap
	local iconSize = height - pad * 2 - (if height < S.HeaderHeight then 4 else 0)
	self.phaseIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	self.phaseIcon.Position = UDim2.fromOffset(pad + iconSize / 2, height / 2)
	self.phaseIcon.Size = UDim2.fromOffset(iconSize, iconSize)
	local leaveLeft = width - pad - d.leave
	self.leave.Position = UDim2.fromOffset(leaveLeft, (height - d.leave) / 2)
	self.leave.Size = UDim2.fromOffset(d.leave, d.leave)
	local pillWidth, pillHeight = d.clockWidth, d.clockHeight
	local pillLeft = leaveLeft - pad / 2 - pillWidth
	self.clockPill.Position = UDim2.fromOffset(pillLeft, (height - pillHeight) / 2)
	self.clockPill.Size = UDim2.fromOffset(pillWidth, pillHeight)
	self.clockIcon.Position = UDim2.fromOffset(3, 2)
	self.clockIcon.Size = UDim2.fromOffset(pillHeight - 4, pillHeight - 4)
	self.clock.Position = UDim2.fromOffset(pillHeight - 1, 1)
	self.clock.Size = UDim2.fromOffset(pillWidth - pillHeight - 4, pillHeight - 2)
	HudParts.setTextSize(self.clock, d.clockText)
	local textLeft = pad + iconSize + pad / 2
	local textRight = (if self.clockPill.Visible then pillLeft else leaveLeft) - pad / 2
	HudParts.setTextSize(self.status, d.status, S.StatusFloor)
	self.status.Position = UDim2.fromOffset(textLeft, (height - d.status - 6) / 2)
	self.status.Size = UDim2.fromOffset(math.max(1, textRight - textLeft), d.status + 6)
end

-- Solo: the player's panel alone, one portrait then fifteen balls in playing order, beside
-- the status panel when it fits and above it otherwise. The row wraps (S.SoloWrapColumns and
-- the rest) when a single line of fifteen does not fit.
function MatchHUD.layoutSolo(self: any, width: number)
	local d = self.bar
	local gap, portraitSize = d.gap, d.portrait
	local short = self.root.AbsoluteSize.Y < S.ShortHeight
	local availableWidth = width - S.HeaderMargin * 2
	local menuLeft, menuRight = self:menuRoom(width)
	local besideRoom = math.min(width - menuLeft - menuRight, availableWidth)
	local function teamWidthFor(columns: number, size: number): number
		return portraitSize + size * columns + S.BallGap * (columns - 1) + gap * 3
	end
	-- The first arrangement that fits: beside Roblox's buttons with the status card beside
	-- it, then under them on one line, then the status under the balls. The row wraps
	-- (S.SoloWrapColumns) when a single line of fifteen does not fit.
	local wrap = S.SoloWrapColumns
	local choice = { columns = wrap, size = S.ShortBallSize, inline = false, beside = false }
	for _, option in
		{
			{ columns = 15, size = d.ball, inline = true, beside = true },
			{ columns = wrap, size = d.ball, inline = true, beside = true },
			{ columns = wrap, size = S.ShortBallSize, inline = true, beside = true },
			{ columns = 15, size = d.ball, inline = true, beside = false },
			{ columns = 15, size = S.ShortBallSize, inline = true, beside = false },
			{ columns = wrap, size = d.ball, inline = true, beside = false },
			{ columns = wrap, size = S.ShortBallSize, inline = true, beside = false },
			{ columns = 15, size = d.ball, inline = false, beside = false },
			{ columns = wrap, size = d.ball, inline = false, beside = false },
		}
	do
		local room = if option.beside then besideRoom else availableWidth
		local beside = if option.inline then gap + d.center else 0
		if teamWidthFor(option.columns, option.size) + beside <= room then
			choice = option
			break
		end
	end
	local columns, ballSize, inline = choice.columns, choice.size, choice.inline
	local rows = math.ceil(15 / columns)
	local rowsHeight = ballSize * rows + S.BallGap * (rows - 1)
	local ballsWidth = ballSize * columns + S.BallGap * (columns - 1)
	local teamWidth = teamWidthFor(columns, ballSize)
	-- On a short screen the status card takes what room is left, up to ShortCenterMax.
	local room = if choice.beside then besideRoom else availableWidth
	local centerWidth = if short and inline
		then math.clamp(room - teamWidth - gap, d.center, S.ShortCenterMax)
		else d.center
	d.center = centerWidth
	self.center.Size = UDim2.fromOffset(centerWidth, d.header)
	local headerHeight = math.max(d.header, rowsHeight + gap * 2)
	local desiredWidth = teamWidth + (if inline then gap + centerWidth else 0)
	local besideMenu = choice.beside
	local top = S.HeaderTop - (if besideMenu then GuiService:GetGuiInset().Y else 0)
	local startX = if besideMenu
		then menuLeft + (besideRoom - desiredWidth) / 2
		else (width - desiredWidth) / 2
	self.headerBottom = top + headerHeight + (if inline then 0 else d.header + gap)
	local team = self.teams[1]
	team.root.Position = UDim2.fromOffset(startX, top)
	team.root.Size = UDim2.fromOffset(teamWidth, headerHeight)
	local ballLeft = portraitSize + gap * 2
	local ballTop = (headerHeight - rowsHeight) / 2
	for n, ball in team.soloBalls do
		local column, row = (n - 1) % columns, math.floor((n - 1) / columns)
		ball.root.Position = UDim2.fromOffset(
			ballLeft + column * (ballSize + S.BallGap),
			ballTop + row * (ballSize + S.BallGap)
		)
		HudParts.sizeBall(ball, ballSize)
	end
	layoutOpen(team, ballLeft, ballTop, ballsWidth, rowsHeight, rows, d)
	self.center.Position = UDim2.fromOffset(
		if inline then startX + teamWidth + gap else (width - centerWidth) / 2,
		top + (if inline then 0 else headerHeight + gap)
	)
end

-- The team of whoever is shooting now.
function MatchHUD.shooterTeam(self: any): number?
	local snapshot = self.snapshot
	for _, seat in (if snapshot then snapshot.seats else {}) do
		if seat.userId == snapshot.shooter then
			return seat.team
		end
	end
	return nil
end

function MatchHUD.reservedHeight(self: any): number
	return self.headerBottom or S.HeaderHeight
end

function MatchHUD.reservedBottom(self: any): number
	local bottom = if self.setup.Visible then self.setupHeight or S.SetupHeight else 0
	return bottom + S.HeaderMargin
end

function MatchHUD.voteKey(self: any): string?
	local vote = self.snapshot and self.snapshot.vote
	if not vote then
		return nil
	end
	return tostring(self.snapshot.epoch) .. ":" .. tostring(vote.deadline)
end

function MatchHUD.closeModal(self: any)
	for _, tween in self.modalTweens do
		tween:Cancel()
	end
	table.clear(self.modalTweens)
	self.modal.Visible = false
	self.modalMode = nil
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self.modal) then
		GuiService.SelectedObject = if self.oldSelection and self.oldSelection.Parent
			then self.oldSelection
			else nil
	end
end

function MatchHUD.showModal(self: any, mode: string)
	self.modalMode = mode
	self.modal.Visible = true
	for _, tween in self.modalTweens do
		tween:Cancel()
	end
	self.modal.BackgroundTransparency = 1
	self.modalTweens = {
		TweenService:Create(
			self.modal,
			TweenInfo.new(S.Motion),
			{ BackgroundTransparency = 1 - S.ModalDim }
		),
	}
	for _, tween in self.modalTweens do
		tween:Play()
	end
	self.dialog.Visible = false
	UIAnim.popIn(self.dialog)
	self.oldSelection = GuiService.SelectedObject
	local team = not self.snapshot.solo and self.snapshot.teamSize > 1
	if mode == "Vote" then
		self.dialogTitle.Text = Copy.VoteTitle
		self.dialogBody.Text = Copy.VoteBody
	else
		self.dialogTitle.Text = Copy.LeaveQuestion
		self.dialogBody.Text = if self.snapshot.solo
			then Copy.LeaveSoloGame
			elseif team then Copy.LeaveTeam
			else Copy.LeaveSolo
	end
	HudParts.setIcon(self.dialogIcon, if mode == "Vote" or team then "Flag" else "Door")
	self.voteProgress.Text = if self.snapshot.solo then "" else Copy.ClocksContinue
	GuiService.SelectedObject = self.no
end

function MatchHUD.openLeave(self: any)
	local snapshot = self.snapshot
	-- The queue is left from its own menu (QueueMenu), or by walking out of the box.
	if
		not snapshot
		or snapshot.phase == "Waiting"
		or snapshot.phase == "Result"
		or self.modal.Visible
	then
		return
	end
	self:showModal("Leave")
end

function MatchHUD.isModal(self: any): boolean
	return self.modal.Visible
end

--- Whether the local shooter may move the cue ball now, and whether it could not follow the
--- pointer. The instruction follows it.
function MatchHUD.setPlacing(self: any, placing: boolean, blocked: boolean)
	self.placingBlocked = placing and blocked
	if placing == self.placing then
		return
	end
	self.placing = placing
	self:layout()
end

function MatchHUD.setInvalidTarget(self: any, invalid: boolean)
	self.invalidTarget = invalid
end

function MatchHUD.setSnapshot(self: any, snapshot: any?, userId: number)
	-- Waiting for the host is the queue menu's (QueueMenu): nobody has a team yet.
	if snapshot and snapshot.phase == "Waiting" then
		snapshot = nil
	end
	local old = self.snapshot
	self.snapshot = snapshot
	self.localUserId = userId
	self.root.Visible = snapshot ~= nil
	if snapshot == nil then
		self:closeModal()
		self.placing, self.placingBlocked = false, false
		return
	end
	local changed = not old
		or old.epoch ~= snapshot.epoch
		or old.turnId ~= snapshot.turnId
		or old.phase ~= snapshot.phase
	if changed then
		self.invalidTarget = false
		if snapshot.phase == "Result" or (old and old.epoch ~= snapshot.epoch) then
			self:closeModal()
		end
	end
	local ours = localTeam(snapshot, userId)
	self.ours = ours
	local previous = if old and old.epoch == snapshot.epoch then self.downIds else nil
	local downIds = {}
	for id = 1, 15 do
		downIds[id] = pocketed(snapshot, id)
	end
	self.downIds = downIds
	local foul = snapshot.foul
	local foulKey = ("%d:%d"):format(snapshot.epoch, snapshot.turnId)
	if snapshot.phase == "Foul" and foul and foulKey ~= self.foulKey then
		self.foulKey = foulKey
		self.foulStart = snapshot.phaseStartedAt
		self.foulUntil = snapshot.phaseStartedAt + S.FoulCardSeconds
		local reason = foul.reason
		if reason == "WrongContact" then
			local group = snapshot.groups and snapshot.groups[foul.team]
			reason = if group == nil
				then "WrongContactOpen"
				elseif eligible(snapshot, foul.team) then "WrongContactEight"
				else "WrongContactOwn"
		end
		self.foulReason.Text = Copy.FoulShort[reason] or ""
	end
	-- Your turn: the cue pops and a shine sweeps the status card, once per turn.
	local turnKey = ("%d:%d"):format(snapshot.epoch, snapshot.turnId)
	local phase = snapshot.phase
	if
		snapshot.shooter == userId
		and self.shoneTurn ~= turnKey
		and (
			phase == "Intro"
			or phase == "Placement"
			or phase == "PocketChoice"
			or phase == "Aiming"
		)
	then
		self.shoneTurn = turnKey
		UIAnim.bounce(self.phaseIcon)
		UIAnim.shine(self.centerFill)
	end
	for side, team in self.teams do
		local teamId = if side == 1 then ours else 3 - ours
		team.teamId = teamId
		local group = snapshot.groups and snapshot.groups[teamId]
		local ready = eligible(snapshot, teamId)
		team.open.Visible = group == nil
		team.openRow.Visible = group == nil
		local openCount = 0
		for _, ball in team.openBalls do
			local down = group == nil and downIds[ball.id]
			ball.root.Visible = down
			if down then
				openCount += 1
				if previous and not previous[ball.id] then
					ball.changedAt = self.lastNow
				end
			end
			ball.down = down
			-- Down, but drawn in its own colours with a small X badge: the groups are not
			-- decided yet, so which balls went down matters.
			HudParts.paintBall(ball, ball.id, false, nil)
			ball.cross.Visible = true
			ball.cross.AnchorPoint = Vector2.new(1, 1)
			ball.cross.Position = UDim2.fromScale(1.15, 1.15)
			ball.cross.Size = UDim2.fromScale(0.62, 0.62)
		end
		team.openCount = openCount
		local seats = {}
		for _, seat in snapshot.seats do
			if seat.team == teamId then
				table.insert(seats, seat)
			end
		end
		table.sort(seats, function(a: any, b: any)
			return a.slot < b.slot
		end)
		for slot, portrait in team.portraits do
			local seat = seats[slot]
			portrait.occupied = seat ~= nil
			portrait.root.Visible = seat ~= nil
			portrait.active.Visible = seat ~= nil
				and seat.userId == snapshot.shooter
				and snapshot.phase ~= "Result"
			portrait.border.Color = if portrait.active.Visible then tone("Green") else tone("Ink")
			portrait.border.Thickness = if portrait.active.Visible
				then S.ActiveEdgePx
				else K.PanelStrokePx
			if seat then
				portrait.gone.Visible = seat.connected == false
				portrait.image.ImageTransparency = if seat.connected == false then 0.6 else 0
				if portrait.userId ~= seat.userId then
					portrait.userId = seat.userId
					portrait.image.Image = ""
					portrait.fallback.Visible = true
					local id = seat.userId
					local cached = self.avatarCache[id]
					if cached then
						portrait.image.Image = cached
						portrait.fallback.Visible = false
					elseif id > 0 then
						task.spawn(function()
							local ok, content, isReady = pcall(function()
								return Players:GetUserThumbnailAsync(
									id,
									Enum.ThumbnailType.HeadShot,
									Enum.ThumbnailSize.Size150x150
								)
							end)
							if
								self.alive
								and ok
								and content
								and isReady
								and portrait.userId == id
							then
								self.avatarCache[id] = content
								portrait.image.Image = content
								portrait.fallback.Visible = false
							end
						end)
					end
				end
			end
		end
		for index, ball in team.balls do
			ball.root.Visible = group ~= nil and not snapshot.solo
			local id = if index == 8 then 8 else index + (if group == "stripes" then 8 else 0)
			local down = downIds[id]
			if down and previous and not previous[id] then
				ball.changedAt = self.lastNow
			end
			ball.down = down
			HudParts.paintBall(ball, id, down, ready)
		end
	end
	-- Solo: one panel, and the row runs first group, other group, then the 8. The first
	-- group shows from the moment its ball drops (the revealed groups) until the reset.
	local solo = snapshot.solo
	self.teams[2].root.Visible = solo == nil
	local first = solo and (solo.first or snapshot.groups[ours])
	local soloReady = eligible(snapshot, ours)
	for index, ball in self.teams[1].soloBalls do
		ball.root.Visible = first ~= nil
		if first then
			local solids = (index <= 7) == (first == "solids")
			local id = if index == 15 then 8 else (index - 1) % 7 + 1 + (if solids then 0 else 8)
			local down = downIds[id]
			if down and previous and not previous[id] then
				ball.changedAt = self.lastNow
			end
			ball.down = down
			HudParts.paintBall(ball, id, down, soloReady)
		end
	end
	local vote = snapshot.vote
	local key = self:voteKey()
	local alreadyYes = vote and (vote.yes[userId] or vote.yes[tostring(userId)])
	if vote and vote.team == ours and key ~= self.respondedVote and not alreadyYes then
		if self.modalMode ~= "Vote" then
			self:showModal("Vote")
		end
	elseif self.modalMode == "Vote" then
		self:closeModal()
	end
	self:layout()
	self:update(self.lastNow)
end

local function drawPerimeter(portrait: any, progress: number, danger: boolean)
	local size = portrait.imageFrame.AbsoluteSize.X
	local thickness = S.ActiveEdgePx
	local remaining = progress * 4
	for index, edge in portrait.edges do
		local fraction = math.clamp(remaining - (index - 1), 0, 1)
		edge.Visible = portrait.active.Visible and fraction > 0
		edge.BackgroundColor3 = if danger then tone("Red") else tone("Green")
		if index == 1 then
			edge.Position = UDim2.fromOffset(-thickness, -thickness)
			edge.Size = UDim2.fromOffset((size + thickness * 2) * fraction, thickness)
		elseif index == 2 then
			edge.Position = UDim2.fromOffset(size, -thickness)
			edge.Size = UDim2.fromOffset(thickness, (size + thickness * 2) * fraction)
		elseif index == 3 then
			edge.Position = UDim2.fromOffset(size - (size + thickness * 2) * fraction, size)
			edge.Size = UDim2.fromOffset((size + thickness * 2) * fraction, thickness)
		else
			edge.Position = UDim2.fromOffset(-thickness, size - (size + thickness * 2) * fraction)
			edge.Size = UDim2.fromOffset(thickness, (size + thickness * 2) * fraction)
		end
	end
end

-- Fade the pieces of the foul popup together.
local function fadeFoul(self: any, transparency: number)
	HudParts.setTextTransparency(self.foulTitle, transparency)
	HudParts.setTextTransparency(self.foulReason, transparency)
	self.foulIcon.ImageTransparency = transparency
end

function MatchHUD.update(self: any, now: number)
	self.lastNow = now
	local snapshot = self.snapshot
	if not snapshot then
		return
	end
	local phase = snapshot.phase
	local isShooter = snapshot.shooter == self.localUserId
	local deadline = snapshot.deadline
	local remaining = if deadline then math.max(0, deadline - now) else 0
	local isClock = deadline ~= nil
		and snapshot.solo == nil -- solo has no clock; the Intro and Foul pass unshown
		and phase ~= "Resolving"
		and phase ~= "Result"
		and phase ~= "CoinFlip"
		and phase ~= "Foul"
	local danger = isClock and remaining <= 5 and phase == "Aiming"
	HudParts.setIcon(self.phaseIcon, phaseIcon(snapshot, isShooter, self.ours or 1))
	-- One line: your turn, theirs (or a teammate's), or what the table is doing.
	local Status = Copy.Status
	local teamTurn = not isShooter and self:shooterTeam() == self.ours
	local line, colour = Status.TheirTurn, "White"
	if phase == "Foul" then
		line, colour = Status.Foul, "Red"
	elseif phase == "Resolving" then
		line = Status.Rolling
	elseif phase == "CoinFlip" then
		line = Status.CoinFlip
	elseif phase == "Result" then
		line = Status.Over
	elseif isShooter or snapshot.solo then
		line, colour = Status.YourTurn, "Green"
	elseif teamTurn then
		line = Status.AllyTurn
	end
	self.status.Text = line
	self.status.TextColor3 = tone(colour)
	HudParts.setTextTransparency(self.status, 0)
	if phase == "Intro" then
		local elapsed = now - snapshot.phaseStartedAt
		HudParts.setTextTransparency(
			self.status,
			1 - math.clamp(math.min(elapsed, remaining) / S.Motion, 0, 1)
		)
	end
	if self.clockPill.Visible ~= isClock then
		self.clockPill.Visible = isClock
		self:layoutStatus()
	end
	self.clock.Text = if isClock
		then (if remaining <= 5 and phase == "Aiming"
			then string.format("%.1f", remaining)
			else tostring(math.ceil(remaining)))
		else ""
	self.clock.TextColor3 = if danger then tone("Red") else tone("White")
	-- Under five seconds the clock throbs.
	self.clockScale.Scale = if danger then 1 + 0.08 * math.abs(math.sin(now * math.pi * 2)) else 1
	self.leave.Visible = phase ~= "Result"
	local progress = if phase == "Aiming"
			and isClock
			and deadline > snapshot.phaseStartedAt
		then remaining / (deadline - snapshot.phaseStartedAt)
		else 1
	for _, team in self.teams do
		for _, portrait in team.portraits do
			drawPerimeter(portrait, math.clamp(progress, 0, 1), danger)
		end
		for _, list in { team.balls, team.openBalls, team.soloBalls } do
			for _, ball in list do
				-- A ball that just went down pops.
				local elapsed = now - ball.changedAt
				ball.scale.Scale = if ball.down
						and elapsed >= 0
						and elapsed < S.Motion * 1.5
					then 1 + (K.Motion.BounceScale - 1) * math.sin(
						elapsed / (S.Motion * 1.5) * math.pi
					)
					else 1
			end
		end
	end
	local placementVisible = isShooter and self.placing
	if self.setup.Visible ~= placementVisible then
		self.setup.Visible = placementVisible
		self:layout()
	end
	local gamepad = UserInputService:GetLastInputType() == Enum.UserInputType.Gamepad1
	self.setupLabel.Text = if self.placingBlocked
		then Copy.PlacementBlocked
		elseif snapshot.breakShot then (if gamepad
			then Copy.BreakPlacementGamepad
			else Copy.BreakPlacement)
		elseif gamepad then Copy.PlacementHintGamepad
		else Copy.PlacementHint
	self.setupLabel.TextColor3 = if self.placingBlocked then tone("Red") else tone("White")
	self.invalid.Visible = self.invalidTarget
		and isShooter
		and (phase == "Aiming" or phase == "Intro" or phase == "Placement")
	self.invalid.Position = UDim2.new(0.5, 0, 1, -(self:reservedBottom() + S.HeaderGap))
	local vote = snapshot.vote
	if self.modalMode == "Vote" and vote then
		local count, total = 0, 0
		for _, seat in snapshot.seats do
			if seat.team == vote.team and seat.connected ~= false then
				total += 1
				if vote.yes[seat.userId] or vote.yes[tostring(seat.userId)] then
					count += 1
				end
			end
		end
		self.voteProgress.Text = string.format(
			Copy.VoteProgress,
			count,
			total,
			math.ceil(math.max(0, vote.deadline - now))
		)
	end
	self:updateFoul(now)
	self:updatePresentation(now)
end

-- The foul popup pops in with the server's foul, holds, and fades at the end.
function MatchHUD.updateFoul(self: any, now: number)
	local snapshot = self.snapshot
	local foulLeft = self.foulUntil - now
	local showFoul = foulLeft > 0 and snapshot.phase ~= "Result" and not self:isModal()
	self.foulGroup.Visible = showFoul
	if not showFoul then
		return
	end
	local margin, gap = S.HeaderMargin, S.HeaderGap
	local width = math.min(S.FoulCardWidth, self.root.AbsoluteSize.X - margin * 2)
	local titleHeight = S.FoulTitleSize + gap
	local reasonHeight = S.FoulReasonSize + gap
	self.foulGroup.Size = UDim2.fromOffset(width, titleHeight + reasonHeight)
	self.foulGroup.Position = UDim2.new(0.5, 0, 0, (self.headerBottom or 0) + gap)
	local elapsed = math.max(0, now - self.foulStart)
	local pop = K.Motion.PopFromScale
		+ (1 - K.Motion.PopFromScale) * UIAnim.backOut(elapsed / K.Motion.PopSeconds)
	self.foulScale.Scale = pop
	fadeFoul(self, 1 - math.clamp(foulLeft / S.FoulCardFadeSeconds, 0, 1))
	-- The whistle sits just left of the word, which is centred.
	local wordWidth = self.foulTitle.TextBounds.X
	local iconSize = S.FoulTitleSize + gap
	self.foulTitle.Position = UDim2.fromOffset(0, 0)
	self.foulTitle.Size = UDim2.fromOffset(width, titleHeight)
	self.foulIcon.AnchorPoint = Vector2.new(1, 0.5)
	self.foulIcon.Position = UDim2.fromOffset(width / 2 - wordWidth / 2 - 4, titleHeight / 2)
	self.foulIcon.Size = UDim2.fromOffset(iconSize, iconSize)
	self.foulReason.Position = UDim2.fromOffset(0, titleHeight)
	self.foulReason.Size = UDim2.fromOffset(width, reasonHeight)
end

-- The coin flip and result card, drawn from the server clock.
function MatchHUD.updatePresentation(self: any, now: number)
	local snapshot = self.snapshot
	local phase = snapshot.phase
	self.overlay.Visible = phase == "CoinFlip" or phase == "Result"
	if not self.overlay.Visible then
		return
	end
	local duration = if phase == "CoinFlip"
		then Config.Multiplayer.CoinSeconds
		else Config.Multiplayer.ResultSeconds
	local elapsed = math.max(0, now - snapshot.phaseStartedAt)
	self.presentationScale.Scale = K.Motion.PopFromScale
		+ (1 - K.Motion.PopFromScale) * UIAnim.backOut(elapsed / K.Motion.PopSeconds)
	self.overlay.GroupTransparency = 1
		- math.clamp(math.min(elapsed, duration - elapsed) / S.Motion, 0, 1)
	local coinPhase = phase == "CoinFlip"
	self.coin.Visible = coinPhase
	self.coinOwner.Visible = coinPhase
	self.resultIcon.Visible = not coinPhase
	if coinPhase and snapshot.coin then
		self.rays.Visible = false
		local coin = snapshot.coin
		local progressCoin = math.clamp(elapsed / (duration * 0.7), 0, 1)
		local turn = (1 - (1 - progressCoin) ^ 3) * math.pi * 8
		local landed = progressCoin >= 1
		local heads = if landed then coin.winnerTeam == coin.headsTeam else math.cos(turn) >= 0
		self.coin.Size =
			UDim2.fromOffset(S.CoinSize * math.max(0.08, math.abs(math.cos(turn))), S.CoinSize)
		self.coin.Rotation = math.sin(turn / 2) * 12 * (1 - progressCoin)
		self.coinGlyph.Text = if heads then Copy.CoinHeadGlyph else Copy.CoinTailGlyph
		self.presentationTitle.Text = if landed
			then (if heads then Copy.Heads else Copy.Tails)
			else Copy.CoinTitle
		self.presentationTitle.TextColor3 = tone("Gold")
		self.coinOwner.Text = string.format(
			Copy.CoinTeams,
			if coin.headsTeam == self.ours then Copy.YourTeam else Copy.OpponentTeam,
			if coin.headsTeam ~= self.ours then Copy.YourTeam else Copy.OpponentTeam
		)
		self.presentationText.Text = if landed
			then string.format(
				Copy.CoinWinner,
				if coin.winnerTeam == self.ours then Copy.YourTeam else Copy.OpponentTeam
			) .. "\n" .. string.format(Copy.PlayerBreaking, nameFor(snapshot, coin.breaker))
			else ""
	else
		local result = snapshot.result
		local win = result and result.winner == self.ours
		local draw = not result or not result.winner
		HudParts.setIcon(self.resultIcon, if draw then "Flag" elseif win then "Trophy" else "Sad")
		self.resultIcon.Rotation = if win then math.sin(elapsed * 3) * 6 else 0
		self.rays.Visible = win == true
		self.rays.Rotation = elapsed * K.Motion.RaysDegreesPerSecond
		self.presentationTitle.Text = if draw then Copy.Draw elseif win then Copy.Win else Copy.Lose
		self.presentationTitle.TextColor3 = if draw
			then tone("White")
			elseif win then tone("Gold")
			else tone("Red")
		self.presentationText.Text = if result
				and snapshot.solo
				and result.reason == "Surrender"
			then Copy.SoloEnded
			elseif result then Copy.ResultReasons[result.reason] or Copy.BackToQueue
			else Copy.BackToQueue
		local resultKey = ("%d"):format(snapshot.epoch)
		if win and self.shoneResult ~= resultKey then
			self.shoneResult = resultKey
			UIAnim.shine(self.presentationFill)
		end
	end
end

function MatchHUD.destroy(self: any)
	self.alive = false
	self:closeModal()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	self.root:Destroy()
	local probe = self.topbarRoom and self.topbarRoom.Parent
	if probe then
		probe:Destroy()
	end
end

return MatchHUD
