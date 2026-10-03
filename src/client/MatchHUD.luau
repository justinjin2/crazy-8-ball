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
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local HudParts = require(script.Parent.HudParts)
local UIAnim = require(script.Parent.UIAnim)
local RankBadge = require(script.Parent.RankBadge)
local Engine = require(Shared:WaitForChild("Rules"):WaitForChild("MatchEngine"))
local UltCatalog = require(Shared:WaitForChild("Ults"):WaitForChild("Catalog"))
local People = require(script.Parent.People)
local Copy = Strings.Match
local M = Config.Multiplayer
local S = M.Style
local K = Config.UI.Kit
local RH = Config.UI.Progress.RankHud
local MatchHUD = {}
MatchHUD.__index = MatchHUD

local tone = HudParts.tone
local RF = Config.UI.RewindFx
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
	-- No name under the portrait (designer, 2026-09-26): the player's rank badge overlaps its
	-- lower edge instead (watchRank; sized in layout). A player who has left gets a red X over
	-- a faded picture.
	local badge = RankBadge.new(root, { size = S.PortraitSize, name = "RankBadge", zIndex = 6 })
	badge.root.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.root.Visible = false
	local gone = HudParts.icon(imageFrame, "X", "Left")
	gone.AnchorPoint = Vector2.new(0.5, 0.5)
	gone.Position = UDim2.fromScale(0.5, 0.5)
	gone.Size = UDim2.fromScale(0.7, 0.7)
	gone.ZIndex = 5
	gone.Visible = false
	-- An opponent's ult (UI_STYLE 11): the icon of the ability they have equipped on the
	-- portrait's inner top corner, greyed and faded until their bar is ready, then in full
	-- colour on a soft gold glow. With no icon, the ult badge (gold when ready), or the kit's
	-- HUD 8 ball while that art is "" too.
	local ult = frame(root, "Ult")
	ult.AnchorPoint = Vector2.new(0.5, 0.5)
	ult.ZIndex = 7
	ult.Visible = false
	local ultGlow = HudParts.icon(ult, "", "Glow")
	ultGlow.Image = K.Art.SoftGlow
	ultGlow.ImageColor3 = tone("Gold")
	ultGlow.ImageTransparency = Config.UI.Ults.OpponentGlowTransparency
	ultGlow.AnchorPoint = Vector2.new(0.5, 0.5)
	ultGlow.Position = UDim2.fromScale(0.5, 0.5)
	ultGlow.Size =
		UDim2.fromScale(Config.UI.Ults.OpponentGlowShare, Config.UI.Ults.OpponentGlowShare)
	ultGlow.ZIndex = 6
	ultGlow.Visible = false
	local ultArt = HudParts.icon(ult, "UltBadge", "Art")
	ultArt.Size = UDim2.fromScale(1, 1)
	ultArt.ZIndex = 7
	local ultBall = HudParts.ball(ult)
	ultBall.root.Size = UDim2.fromScale(1, 1)
	ultBall.root.ZIndex = 7
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
	-- The shot clock runs round the portrait of whoever is shooting, draining as it runs: a
	-- rounded ring on the portrait's own outline, drawn in two clipped halves (left, right). In
	-- each half a hard-edged gradient on the ring's stroke turns about the centre, so the
	-- visible part is a wedge from twelve o'clock; drawPerimeter turns it, layout sizes it.
	local halves = {}
	for _, side in { "Left", "Right" } do
		local half = frame(imageFrame, "Clock" .. side)
		half.ClipsDescendants = true
		half.ZIndex = 3
		local ring = frame(half, "Ring")
		ring.ZIndex = 3
		corner(ring, S.PortraitCornerPx)
		local stroke = Instance.new("UIStroke")
		stroke.Color = tone("Green")
		stroke.Thickness = S.ActiveEdgePx
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = ring
		local sweep = Instance.new("UIGradient")
		sweep.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(0.501, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
		sweep.Parent = stroke
		table.insert(halves, { half = half, ring = ring, stroke = stroke, sweep = sweep })
	end
	return {
		root = root,
		imageFrame = imageFrame,
		image = avatar,
		fallback = fallback,
		gone = gone,
		active = active,
		border = border,
		halves = halves,
		badge = badge,
		ult = ult,
		ultArt = ultArt,
		ultGlow = ultGlow,
		ultBall = ultBall,
		ultLit = nil,
		ultIcon = nil, -- the icon shown (the opponent's equipped ult's), "" for the badge
		rankConnections = {},
		rankPending = false,
		userId = nil,
		occupied = false,
	}
end

-- The icon of the ult `userId` plays with: their UltEquipped attribute (the server keeps it
-- to the ult it would arm), a pretend player's the default; "" when it has none.
local function ultIconOf(userId: number?): string
	local who = People.owner(userId) -- a player or a bot (the Bots lane)
	local equipped = if who then who:GetAttribute("UltEquipped") else nil
	local id = if type(equipped) == "string" and UltCatalog.exists(equipped)
		then equipped
		else Config.Ults.Default
	return UltCatalog.icon(id)
end

-- Light an opponent's ult icon (ready) or fade it; `shown` false hides it. `icon` is their
-- ult's icon ("" falls back to the badge).
local function paintUlt(portrait: any, shown: boolean, lit: boolean, icon: string)
	portrait.ult.Visible = shown
	if not shown or (portrait.ultLit == lit and portrait.ultIcon == icon) then
		return
	end
	local becameLit = lit and portrait.ultLit ~= lit
	portrait.ultLit = lit
	portrait.ultIcon = icon
	local art = if lit then K.Icons.UltBadgeGold else K.Icons.UltBadge
	if art == "" then
		art = K.Icons.UltBadge
	end
	if icon ~= "" then
		art = icon
	end
	local fade = if lit then 0 else Config.UI.Ults.OpponentDimTransparency
	portrait.ultArt.Image = art
	portrait.ultArt.Visible = art ~= ""
	portrait.ultArt.ImageTransparency = fade
	portrait.ultArt.ImageColor3 = if lit then Color3.new(1, 1, 1) else tone("Grey")
	portrait.ultGlow.Visible = lit and icon ~= "" and portrait.ultGlow.Image ~= ""
	local ball = portrait.ultBall
	ball.root.Visible = art == ""
	HudParts.paintBall(ball, 8, false)
	ball.sphere.BackgroundTransparency = fade
	ball.disc.BackgroundTransparency = fade
	ball.number.TextTransparency = fade
	ball.ring.Color = if lit then tone("Gold") else tone("Ink")
	ball.ring.Thickness = if lit then K.Ball.StrokePx + 1 else K.Ball.StrokePx
	ball.ring.Transparency = fade
	if becameLit then
		UIAnim.bounce(portrait.ult)
	end
end

--- The shot clock's time left, in seconds: `deadline - max(now, pausedUntil)`. While an ult is
--- being activated (its cutscene and arming) the clock stands still; the server has already
--- moved the deadline on by that pause (Ults/Match). Main's last-seconds tick uses it too.
function MatchHUD.clockLeft(snapshot: any, now: number): number
	local deadline = snapshot and snapshot.deadline
	if type(deadline) ~= "number" then
		return 0
	end
	local ults = snapshot.ults
	local paused = if type(ults) == "table" then ults.pausedUntil else nil
	local from = if type(paused) == "number" and paused > now then paused else now
	return math.max(0, deadline - from)
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

-- The top bar's sizes: full, or compact on short screens (a phone on its side), before the
-- bar is scaled to fit (layout).
local function barSizes(short: boolean): any
	return {
		portrait = if short then S.ShortPortraitSize else S.PortraitSize,
		header = if short then S.ShortHeaderHeight else S.HeaderHeight,
		leave = if short then S.ShortLeaveSize else S.LeaveSize,
		clockWidth = if short then S.ShortCenterClockWidth else S.CenterClockWidth,
		clockText = if short then S.ShortCenterClockTextSize else S.CenterClockTextSize,
		moveWidth = if short then S.ShortMoveClockWidth else S.MoveClockWidth,
		moveHeight = if short then S.ShortMoveClockHeight else S.MoveClockHeight,
		moveText = if short then S.ShortMoveClockTextSize else S.MoveClockTextSize,
		status = if short then S.ShortOpenLabelSize else S.StatusSize, -- OPEN TABLE
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
	for _, property in { "AbsoluteSize", "AbsolutePosition" } do
		table.insert(
			self.connections,
			self.topbarRoom:GetPropertyChangedSignal(property):Connect(function()
				self:layout()
			end)
		)
	end
	-- The top bar: both teams, the clock between them and Leave at the right end, in one
	-- container laid out at its natural size and scaled down to fit the room beside Roblox's
	-- buttons (layout), so it stays one row on every screen (designer, 2026-09-26).
	self.topBar = frame(self.root, "TopBar")
	self.barScale = Instance.new("UIScale")
	self.barScale.Parent = self.topBar
	self.teams = { makeTeam(self.topBar, "LocalTeam"), makeTeam(self.topBar, "OtherTeam") }
	-- Solo: fifteen slots on the local panel in playing order (first group, other group, 8).
	self.teams[1].soloBalls, self.teams[2].soloBalls = {}, {}
	for _ = 1, 15 do
		table.insert(self.teams[1].soloBalls, HudParts.ball(self.teams[1].root))
	end

	-- The shot clock, big, between the two teams; only while a clock runs.
	self.clockPill = HudParts.pill(self.topBar, "Clock")
	self.clockScale = Instance.new("UIScale")
	self.clockScale.Parent = self.clockPill
	self.clockIcon = HudParts.icon(self.clockPill, "Stopwatch")
	self.clock = text(self.clockPill, "Timer", S.CenterClockTextSize, "")
	-- With ball in hand: the time left to move the cue ball, in blue like its MOVE ring,
	-- under the big clock (which holds at the full shot clock until it runs out).
	self.movePill = HudParts.pill(self.topBar, "MoveClock", tone("Blue"))
	self.movePill.Visible = false
	self.moveIcon = HudParts.icon(self.movePill, "Hand")
	self.moveText = text(self.movePill, "Timer", S.MoveClockTextSize, "")
	-- A rematch's series score, your side first ("Series 1-0"), in the same spot while the
	-- move pill is not there (designer, 2026-09-28).
	self.seriesPill = HudParts.pill(self.topBar, "Series", tone("Gold"))
	self.seriesPill.Visible = false
	self.seriesText = text(self.seriesPill, "Score", S.MoveClockTextSize, "")
	self.seriesText.AutoLocalize = false
	-- A No ults match (the global queue's Ults Off, settings.abilities false): a small grey NO
	-- ULTS pill in the same row, beside the move or series pill when one shows.
	self.noUltsPill =
		HudParts.pill(self.topBar, "NoUlts", HudParts.color(Config.UI.Ults.NoUltsColor))
	self.noUltsPill.Visible = false
	self.noUltsText =
		text(self.noUltsPill, "Words", Config.UI.Ults.NoUltsTextPx, Strings.Ults.Hud.NoUlts)
	self.noUltsText.TextWrapped = false
	self.noUlts = false
	-- Rewind's redo (ABILITIES_PROMPT 7.6): a pink SECOND CHANCE: 10s pill in the same row
	-- while the redo's turn lasts (snapshot.redoClock). Never in a No ults match.
	self.redoPill = HudParts.pill(self.topBar, "SecondChance", HudParts.color(RF.PillColor))
	self.redoPill.Visible = false
	self.redoText = text(
		self.redoPill,
		"Words",
		Config.UI.Ults.NoUltsTextPx,
		Copy.SecondChance:format(Config.Ults.Shared.RewindRedoSeconds)
	)
	self.redoText.TextWrapped = false
	self.ultReserve = 0 -- the ult HUD's room at the bottom (setUltReserve)
	-- Leave: a small red door at the bar's right end, beside the right-hand team.
	self.leave = candy(self.topBar, "", function()
		self:openLeave()
	end, "Red", "Door")
	HudParts.setMinHit(self.leave, S.TouchTargetPx)

	-- The turn popup: whose turn it is, for a moment when the turn passes, like the foul
	-- popup but smaller (it replaced the status card; designer, 2026-09-26).
	self.turnGroup = frame(self.root, "TurnPopup")
	self.turnGroup.AnchorPoint = Vector2.new(0.5, 0)
	self.turnGroup.Visible = false
	self.turnScale = Instance.new("UIScale")
	self.turnScale.Parent = self.turnGroup
	self.turnIcon = HudParts.icon(self.turnGroup, "Cue")
	self.turnTitle = text(self.turnGroup, "Title", S.TurnPopupTitleSize, "")
	self.turnTitle.TextWrapped = false
	-- The same popup says which group you are once the break's first legal ball decides them:
	-- a solid or striped ball beside the words instead of the icon.
	self.turnBall = HudParts.ball(self.turnGroup)
	self.turnBall.root.Visible = false
	self.turnIsGroup = false -- the popup shows the group, not a turn
	self.popupSeconds = S.TurnPopupSeconds -- how long the current popup stays up
	self.groupEpoch = nil -- the match whose group reveal is being watched
	self.knownGroup = nil -- our group in that match as last seen (nil: not decided yet)
	self.turnKey = "" -- the turn the popup is for
	self.turnStart = 0 -- when it pops (after a foul popup, if one is up)
	self.soloShown = nil -- the solo game whose one turn popup has played

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

	-- The leave / surrender question; its see-through backdrop blocks taps behind it.
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

	-- The coin flip and the result: a card popping up over the game (no dimming), faded as one.
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
	local snapshot = self.snapshot
	local solo = snapshot ~= nil and snapshot.solo ~= nil
	local count = if snapshot and not solo then snapshot.teamSize else 1
	local portraitSize, ballSize, height = d.portrait, d.ball, d.header
	local portraitsWidth = portraitSize * count + S.PortraitGap * (count - 1)
	-- One row always: eight a side, or solo's fifteen in playing order.
	local columns = if solo then 15 else 8
	local ballsWidth = ballSize * columns + S.BallGap * (columns - 1)
	local teamWidth = portraitsWidth + ballsWidth + gap * 3
	-- Left to right: our team, the clock, their team, Leave (solo: the one team, then Leave).
	local clockLeft = teamWidth + gap
	local otherLeft = clockLeft + d.clockWidth + gap
	local leaveLeft = if solo then teamWidth + gap else otherLeft + teamWidth + gap
	local natural = leaveLeft + d.leave
	-- The auto-fit: laid out at its natural size, then scaled down (never up) to the free room
	-- beside Roblox's buttons, in Roblox's own top row, so it is one row on every screen.
	local menuLeft, menuRight = self:menuRoom(width)
	local room = math.max(1, width - menuLeft - menuRight)
	local scale = math.min(1, room / natural)
	self.barScale.Scale = scale
	self.topBar.Size = UDim2.fromOffset(natural, height)
	local top = self:barTop()
	self.topBar.Position = UDim2.fromOffset(menuLeft + (room - natural * scale) / 2, top)
	self.headerBottom = top + height * scale
	for i, team in self.teams do
		team.root.Position = UDim2.fromOffset(if i == 1 then 0 else otherLeft, 0)
		team.root.Size = UDim2.fromOffset(teamWidth, height)
		-- Portraits on the outside edge, centred in the card's height beside the balls.
		local portraitLeft = if i == 1 then gap else teamWidth - portraitsWidth - gap
		for n, portrait in team.portraits do
			portrait.root.Position = UDim2.fromOffset(
				portraitLeft + (n - 1) * (portraitSize + S.PortraitGap),
				(height - portraitSize) / 2
			)
			portrait.root.Size = UDim2.fromOffset(portraitSize, portraitSize)
			portrait.imageFrame.Size = UDim2.fromOffset(portraitSize, portraitSize)
			-- The rank badge, centred on the portrait's lower edge (a little above it), so it
			-- overlaps the edge rather than growing the bar.
			local badgeSize = portraitSize * RH.PortraitBadgeShare
			portrait.badge:setSize(badgeSize)
			portrait.badge.root.Position = UDim2.new(0.5, 0, 1, -badgeSize * RH.PortraitBadgeRaise)
			-- The ult icon on the top corner facing the balls (their team's left one).
			local ultSize = math.floor(portraitSize * Config.UI.Ults.OpponentIconShare)
			portrait.ult.Size = UDim2.fromOffset(ultSize, ultSize)
			portrait.ult.Position =
				UDim2.fromOffset(if i == 1 then portraitSize else 0, math.floor(ultSize * 0.3))
			HudParts.sizeBall(portrait.ultBall, ultSize)
			portrait.root.Visible = n <= count and portrait.occupied
			-- The clock ring's halves, with room outside the portrait for the stroke. In the
			-- bar's own pixels: the bar's UIScale shrinks them with everything else.
			local ringRoom = S.ActiveEdgePx + 1
			local halfWidth = portraitSize / 2
			for side, h in portrait.halves do
				local left = if side == 1 then -ringRoom else halfWidth
				h.half.Position = UDim2.fromOffset(left, -ringRoom)
				h.half.Size = UDim2.fromOffset(halfWidth + ringRoom, portraitSize + ringRoom * 2)
				h.ring.Position = UDim2.fromOffset(-left, ringRoom)
				h.ring.Size = UDim2.fromOffset(portraitSize, portraitSize)
			end
		end
		local ballLeft = if i == 1 then portraitsWidth + gap * 2 else gap
		local ballTop = (height - ballSize) / 2
		local list = if solo and i == 1 then team.soloBalls else team.balls
		for n, ball in list do
			ball.root.Position =
				UDim2.fromOffset(ballLeft + (n - 1) * (ballSize + S.BallGap), ballTop)
			HudParts.sizeBall(ball, ballSize)
		end
		layoutOpen(team, ballLeft, ballTop, ballsWidth, ballSize, 1, d)
	end
	-- The clock, centred between the teams; it throbs about its centre in the last seconds.
	local clockWidth = d.clockWidth
	self.clockPill.AnchorPoint = Vector2.new(0.5, 0.5)
	self.clockPill.Position = UDim2.fromOffset(clockLeft + clockWidth / 2, height / 2)
	self.clockPill.Size = UDim2.fromOffset(clockWidth, height)
	local iconSize = height - 8
	self.clockIcon.Position = UDim2.fromOffset(5, 4)
	self.clockIcon.Size = UDim2.fromOffset(iconSize, iconSize)
	self.clock.Position = UDim2.fromOffset(iconSize + 6, 2)
	self.clock.Size = UDim2.fromOffset(clockWidth - iconSize - 12, height - 4)
	HudParts.setTextSize(self.clock, d.clockText)
	local moveHeight = d.moveHeight
	self.movePill.AnchorPoint = Vector2.new(0.5, 0)
	self.movePill.Position = UDim2.fromOffset(clockLeft + clockWidth / 2, height + gap)
	self.movePill.Size = UDim2.fromOffset(d.moveWidth, moveHeight)
	local moveIconSize = moveHeight - 6
	self.moveIcon.Position = UDim2.fromOffset(5, 3)
	self.moveIcon.Size = UDim2.fromOffset(moveIconSize, moveIconSize)
	self.moveText.Position = UDim2.fromOffset(moveIconSize + 6, 1)
	self.moveText.Size = UDim2.fromOffset(d.moveWidth - moveIconSize - 12, moveHeight - 2)
	HudParts.setTextSize(self.moveText, d.moveText)
	self.seriesPill.AnchorPoint = Vector2.new(0.5, 0)
	self.seriesPill.Position = self.movePill.Position
	self.seriesPill.Size = self.movePill.Size
	self.seriesText.Position = UDim2.fromOffset(6, 1)
	self.seriesText.Size = UDim2.fromOffset(d.moveWidth - 12, moveHeight - 2)
	HudParts.setTextSize(self.seriesText, d.moveText)
	-- NO ULTS: as tall as the move pill, as wide as its words; laid out in update, where it
	-- knows whether it sits alone or beside the move or series pill.
	local noUltsText = Config.UI.Ults.NoUltsTextPx
	HudParts.setTextSize(self.noUltsText, noUltsText)
	local noUltsWidth = TextService:GetTextSize(
		self.noUltsText.Text,
		noUltsText,
		self.noUltsText.Font,
		Vector2.new(1000, 100)
	).X + Config.UI.Ults.NoUltsPadPx * 2
	self.noUltsPill.AnchorPoint = Vector2.new(0.5, 0)
	self.noUltsPill.Size = UDim2.fromOffset(noUltsWidth, moveHeight)
	self.noUltsText.Position = UDim2.fromOffset(0, 1)
	self.noUltsText.Size = UDim2.fromOffset(noUltsWidth, moveHeight - 2)
	local redoWidth = TextService:GetTextSize(
		self.redoText.Text,
		noUltsText,
		self.redoText.Font,
		Vector2.new(1000, 100)
	).X + Config.UI.Ults.NoUltsPadPx * 2
	HudParts.setTextSize(self.redoText, noUltsText)
	self.redoPill.AnchorPoint = Vector2.new(0.5, 0)
	self.redoPill.Size = UDim2.fromOffset(redoWidth, moveHeight)
	self.redoText.Position = UDim2.fromOffset(0, 1)
	self.redoText.Size = UDim2.fromOffset(redoWidth, moveHeight - 2)
	self.redoWidth = redoWidth
	self.noUltsRow = {
		centre = clockLeft + clockWidth / 2,
		top = height + gap,
		width = noUltsWidth,
		beside = d.moveWidth,
		gap = gap,
	}
	-- The popups under the bar drop below the move pill while it shows.
	self.moveBottom = self.headerBottom + (gap + moveHeight) * scale
	self.leave.Position = UDim2.fromOffset(leaveLeft, (height - d.leave) / 2)
	self.leave.Size = UDim2.fromOffset(d.leave, d.leave)
	-- The placement instruction: one thin line centred at the bottom, as wide as its words.
	local setupHeight = if short then S.ShortSetupHeight else S.SetupHeight
	-- Over the ult bar while it shows (setUltReserve).
	self.setup.Position = UDim2.new(0.5, 0, 1, -(margin + self.ultReserve))
	self.setupHeight = setupHeight
	self.setupTextSize = if short then S.ShortSetupTextSize else S.SetupTextSize
	layoutIconLine(self.setupLine, setupHeight)
	HudParts.setTextSize(self.setupLabel, self.setupTextSize)
	self:fitSetup()
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
	self.presentationText.Position = UDim2.new(0, gap * 2, 1, -S.ButtonHeight * 1.2 - gap)
	self.presentationText.Size = UDim2.new(1, -gap * 4, 0, S.ButtonHeight * 1.2)
end

-- The hint pill just wide enough for its icon and words, never wider than SetupMaxWidth or
-- the screen (a longer line, a translation say, shrinks its words to fit instead).
function MatchHUD.fitSetup(self: any)
	local height = self.setupHeight or S.SetupHeight
	local words = TextService:GetTextSize(
		self.setupLabel.Text,
		self.setupTextSize or S.SetupTextSize,
		self.setupLabel.Font,
		Vector2.new(10000, 1000)
	).X
	-- layoutIconLine's room: the icon and its margins, the right margin, and the outline.
	local chrome = math.floor(height * 0.25)
		+ math.floor(height * 0.8)
		+ 6
		+ math.floor(height * 0.3)
		+ 4
	local most = math.min(S.SetupMaxWidth, self.width - S.HeaderMargin * 2)
	self.setup.Size = UDim2.fromOffset(math.min(most, words + chrome), height)
end

-- Where the bar's top goes, in the root's pixels: HeaderTop below the top of Roblox's own top
-- row, measured from where that row really is (ScreenInsets.TopbarSafeInsets) rather than from
-- GuiService's inset. On some phones (an iPhone 17 Pro) this screen starts lower than the inset
-- says, and the bar sat below the row, over the table (designer, 2026-09-27).
function MatchHUD.barTop(self: any): number
	local room = self.topbarRoom
	local probe = room and room.Parent
	if room and probe and probe.Parent and room.AbsoluteSize.Y > 0 then
		return room.AbsolutePosition.Y - self.root.AbsolutePosition.Y + S.HeaderTop
	end
	return S.HeaderTop - GuiService:GetGuiInset().Y
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
	return bottom + S.HeaderMargin + self.ultReserve
end

--- The ult HUD's room at the bottom of the screen (UltHud.reservedBottom, 0 while it is
--- hidden): the ball-in-hand hint and the wrong-ball line sit above it.
function MatchHUD.setUltReserve(self: any, px: number)
	px = math.max(0, math.floor(px + 0.5))
	if px == self.ultReserve then
		return
	end
	self.ultReserve = px
	self.setup.Position = UDim2.new(0.5, 0, 1, -(S.HeaderMargin + px))
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
--- Whether the local shooter may strike the cue ball again in Time Stop's stopped time (Main's
--- frozenTurn). The instruction line says so.
function MatchHUD.setFrozenAim(self: any, frozen: boolean)
	if frozen == (self.frozenAim == true) then
		return
	end
	self.frozenAim = frozen
	self:layout()
end

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
	-- Ults (absent on an old snapshot: off): each opponent's icon, and NO ULTS for a No ults
	-- queue match.
	local ults = snapshot.ults
	local ultsOn = type(ults) == "table" and ults.on == true and type(ults.bars) == "table"
	self.noUlts = type(snapshot.settings) == "table"
		and snapshot.settings.abilities == false
		and snapshot.solo == nil
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
	-- A new turn pops the turn popup: yours, an ally's or the opponent's. It waits for a foul
	-- popup that is still up. Solo is always your turn, so only its first turn pops.
	local turnKey = ("%d:%d"):format(snapshot.epoch, snapshot.turnId)
	local phase = snapshot.phase
	local shooting = phase == "Intro"
		or phase == "Placement"
		or phase == "PocketChoice"
		or phase == "Aiming"
	local soloKey = if snapshot.solo then tostring(snapshot.epoch) else nil
	if shooting and self.turnKey ~= turnKey and (soloKey == nil or self.soloShown ~= soloKey) then
		self.turnKey = turnKey
		self.soloShown = soloKey or self.soloShown
		local now = workspace:GetServerTimeNow()
		self.turnStart = math.max(now, self.foulUntil)
		local Status = Copy.Status
		local mine = snapshot.shooter == userId or snapshot.solo ~= nil
		local ally = not mine and self:shooterTeam() == ours
		self.turnTitle.Text = if mine
			then Status.YourTurn
			elseif ally then Status.AllyTurn
			else Status.TheirTurn
		self.turnTitle.TextColor3 = if mine then tone("Green") else tone("White")
		HudParts.setIcon(self.turnIcon, if mine then "Cue" else "Hourglass")
		self.turnIsGroup = false
		self.popupSeconds = S.TurnPopupSeconds
		self.turnMine = mine
		self.turnBounced = false
	end
	-- The groups are decided (the replay dropped the ball that picks them): tell each player
	-- theirs, YOU ARE SOLIDS or YOU ARE STRIPES (designer, 2026-09-27). Only when they become
	-- known during this match, not for someone arriving after.
	local myGroup = snapshot.groups and snapshot.groups[ours]
	if self.groupEpoch ~= snapshot.epoch then
		self.groupEpoch, self.knownGroup = snapshot.epoch, myGroup
	elseif myGroup ~= self.knownGroup then
		self.knownGroup = myGroup
		if myGroup then
			local solids = myGroup == "solids"
			self.turnKey = turnKey
			self.turnStart = math.max(workspace:GetServerTimeNow(), self.foulUntil)
			self.popupSeconds = S.GroupPopupSeconds
			self.turnTitle.Text = if solids then Copy.GroupPopup.Solids else Copy.GroupPopup.Stripes
			self.turnTitle.TextColor3 = tone("Gold")
			HudParts.setIcon(self.turnIcon, nil)
			HudParts.paintBall(self.turnBall, if solids then 1 else 9, false)
			self.turnIsGroup = true
			self.turnMine = false
			self.turnBounced = true
		end
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
			-- Their ult: shown on the other side's portraits while ults are on, lit when ready.
			local ultBar = seat ~= nil and side == 2 and ultsOn and ults.bars[tostring(seat.userId)]
				or nil
			paintUlt(
				portrait,
				type(ultBar) == "table",
				type(ultBar) == "table" and ultBar.ready == true,
				if type(ultBar) == "table" then ultIconOf(seat.userId) else ""
			)
			-- The border stays ink: the shooter's green is the clock ring over it, so as the
			-- ring drains the ink shows through (a green border under it hid the draining).
			portrait.border.Color = tone("Ink")
			portrait.border.Thickness = K.PanelStrokePx
			if seat then
				portrait.gone.Visible = seat.connected == false
				portrait.image.ImageTransparency = if seat.connected == false then 0.6 else 0
				if portrait.userId ~= seat.userId then
					portrait.userId = seat.userId
					self:watchRank(portrait, seat.userId, seat.bot)
					portrait.image.Image = ""
					portrait.fallback.Visible = true
					-- A bot's portrait (the Bots lane): its avatar's account, or the robot.
					local id, picture = People.portrait(seat.userId, seat.bot)
					local cached = if id then self.avatarCache[id] else nil
					if picture then
						portrait.image.Image = picture
						portrait.fallback.Visible = false
					elseif cached then
						portrait.image.Image = cached
						portrait.fallback.Visible = false
					elseif id and id > 0 then
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
								and portrait.userId == seat.userId
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
	-- The live server clock, not lastNow: before the first frame lastNow can be a reading from
	-- before the clock synced (0), which drew the clock as the whole server time.
	self:update(workspace:GetServerTimeNow())
end

-- The small rank badge under a portrait: the seated player's rank from their attributes
-- (RankTier, RankDivision), kept up to date, so it pops when they rank up as the match ends.
-- Hidden when there is no such Player (the Studio QA fixture's made-up players).
function MatchHUD.watchRank(self: any, portrait: any, userId: number, bot: any?)
	for _, connection in portrait.rankConnections do
		connection:Disconnect()
	end
	table.clear(portrait.rankConnections)
	local badge = portrait.badge
	local player = People.owner(userId) -- a player or a bot's stand-in (the Bots lane)
	if not player then
		-- A bot whose body is not here yet: the badge from its seat.
		if type(bot) == "table" and type(bot.tier) == "string" then
			badge:set(bot.tier, bot.division or 1, false)
			badge.root.Visible = true
			return
		end
		badge.root.Visible = false
		return
	end
	local shown: string? = nil
	local function refresh()
		local tier = player:GetAttribute("RankTier")
		local division = player:GetAttribute("RankDivision")
		if type(tier) ~= "string" then
			badge.root.Visible = false -- their save is not in yet
			return
		end
		local d = if type(division) == "number" then division else 0
		local key = tier .. ":" .. d
		badge:set(tier, d, shown ~= nil and shown ~= key)
		shown = key
		badge.root.Visible = true
	end
	-- The tier and division change together: one refresh for both.
	local function changed()
		if portrait.rankPending then
			return
		end
		portrait.rankPending = true
		task.defer(function()
			portrait.rankPending = false
			if self.alive and portrait.userId == userId then
				refresh()
			end
		end)
	end
	for _, attribute in { "RankTier", "RankDivision" } do
		table.insert(
			portrait.rankConnections,
			player:GetAttributeChangedSignal(attribute):Connect(changed)
		)
	end
	refresh()
end

-- The ring shows the arc from twelve o'clock clockwise to `progress` of the way round. A
-- gradient turned to R degrees is opaque on the clock angles R - 180 to R, so the right half
-- (0 to 180) shows up to the arc's end with R in 0..180 and the left half (180 to 360) with
-- R in 180..360.
local function drawPerimeter(portrait: any, progress: number, danger: boolean)
	local angle = progress * 360
	local shown = portrait.active.Visible and progress > 0
	for side, h in portrait.halves do
		h.half.Visible = shown
		h.stroke.Color = if danger then tone("Red") else tone("Green")
		h.sweep.Rotation = if side == 1
			then math.clamp(angle, 180, 360)
			else math.clamp(angle, 0, 180)
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
	-- Held while an ult is activated (the cutscene and its arming): MatchHUD.clockLeft.
	local remaining = MatchHUD.clockLeft(snapshot, now)
	local isClock = deadline ~= nil
		and snapshot.solo == nil -- solo has no clock; the Intro and Foul pass unshown
		and phase ~= "Resolving"
		and phase ~= "Result"
		and phase ~= "CoinFlip"
		and phase ~= "Foul"
		and phase ~= "Rewinding" -- Rewind's moment: its redo clock comes after
		and phase ~= "Frozen" -- Time Stop: the clock face on the cloth counts the 5 s
	-- With ball in hand the shot clock starts when moving time ends (MatchEngine): the move pill
	-- counts the moving time and the big clock holds at the full shot clock until it runs out
	-- (designer, 2026-09-27), so the time to move never reads as the time to shoot. Not on the
	-- break: moving and shooting share one clock there, the big one.
	local shotClock = Engine.isShotClock(phase, snapshot.breakShot)
	local placing = isClock and phase == "Placement" and not shotClock
	self.movePill.Visible = placing
	-- The series from its second game on, while a game is played and the move pill is away.
	local series = snapshot.series
	local seriesShown = not placing
		and type(series) == "table"
		and (series.games or 0) >= 1
		and phase ~= "Result"
		and phase ~= "Waiting"
		and snapshot.solo == nil
	self.seriesPill.Visible = seriesShown
	if seriesShown then
		local ours = if localTeam(snapshot, self.localUserId) == 2 then 2 else 1
		local theirs = 3 - ours
		self.seriesText.Text =
			Strings.PostMatch.SeriesPill:format(series.wins[ours] or 0, series.wins[theirs] or 0)
	end
	-- NO ULTS: centred under the clock, or just right of the move or series pill.
	local row = self.noUltsRow
	self.noUltsPill.Visible = self.noUlts and phase ~= "Result"
	if row then
		local besideOne = placing or seriesShown
		local x = if besideOne
			then row.centre + row.beside / 2 + row.gap + row.width / 2
			else row.centre
		self.noUltsPill.Position = UDim2.fromOffset(x, row.top)
	end
	local redo = snapshot.redoClock == true
		and (phase == "Intro" or phase == "Placement" or phase == "Aiming")
	self.redoPill.Visible = redo
	if row and redo then
		local besideOne = placing or seriesShown
		local x = if besideOne
			then row.centre + row.beside / 2 + row.gap + self.redoWidth / 2
			else row.centre
		self.redoPill.Position = UDim2.fromOffset(x, row.top)
	end
	self.popupTop = if placing
			or seriesShown
			or self.noUltsPill.Visible
			or redo
		then self.moveBottom
		else self.headerBottom
	if placing then
		self.moveText.Text = string.format(Copy.MoveClock, math.ceil(remaining))
	end
	local danger = isClock and remaining <= 5 and shotClock
	self.clockPill.Visible = isClock
	self.clock.Text = if not isClock
		then ""
		elseif placing then tostring(M.ShotSeconds)
		elseif danger then string.format("%.1f", remaining)
		else tostring(math.ceil(remaining))
	self.clock.TextColor3 = if danger then tone("Red") else tone("White")
	-- Under five seconds the clock throbs.
	self.clockScale.Scale = if danger then 1 + 0.08 * math.abs(math.sin(now * math.pi * 2)) else 1
	self.leave.Visible = phase ~= "Result"
	-- The ring drains with the big clock (calling the pocket, aiming), each over its own clock;
	-- it stays full through the turn's introduction and while the cue ball is being moved.
	-- An ult activated in this phase moved the deadline on by its pause: the ring's full length
	-- leaves that out, so the ring holds through the pause and then drains as before.
	local armed = type(snapshot.ults) == "table" and snapshot.ults.armed or nil
	local pause = 0
	if
		type(armed) == "table"
		and type(armed.at) == "number"
		and type(armed.readyAt) == "number"
		and armed.at >= snapshot.phaseStartedAt
	then
		pause = math.max(0, armed.readyAt - armed.at)
	end
	local full = if deadline then deadline - snapshot.phaseStartedAt - pause else 0
	local progress = if isClock
			and phase ~= "Intro"
			and not placing
			and full > 0
		then remaining / full
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
	local placementVisible = isShooter and (self.placing or self.frozenAim == true)
	if self.setup.Visible ~= placementVisible then
		self.setup.Visible = placementVisible
		self:layout()
	end
	local gamepad = UserInputService:GetLastInputType() == Enum.UserInputType.Gamepad1
	local hint = if self.frozenAim
		then Copy.TimeStopHint
		elseif self.placingBlocked then Copy.PlacementBlocked
		elseif snapshot.breakShot then (if gamepad
			then Copy.BreakPlacementGamepad
			else Copy.BreakPlacement)
		elseif gamepad then Copy.PlacementHintGamepad
		else Copy.PlacementHint
	if self.setupLabel.Text ~= hint then
		self.setupLabel.Text = hint
		self:fitSetup()
	end
	self.setupLabel.TextColor3 = if self.placingBlocked and not self.frozenAim
		then tone("Red")
		else tone("White")
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
	self:updateTurn(now)
	self:updatePresentation(now)
end

-- The turn popup: pops in when its turn starts (or when a foul popup before it ends), holds,
-- and fades out. Only while that turn lasts.
function MatchHUD.updateTurn(self: any, now: number)
	local snapshot = self.snapshot
	local key = ("%d:%d"):format(snapshot.epoch, snapshot.turnId)
	local elapsed = now - self.turnStart
	local left = self.popupSeconds - elapsed
	local show = key == self.turnKey
		and elapsed >= 0
		and left > 0
		and snapshot.phase ~= "Result"
		and not self:isModal()
	self.turnGroup.Visible = show
	if not show then
		return
	end
	if self.turnMine and not self.turnBounced then
		self.turnBounced = true
		UIAnim.bounce(self.turnIcon) -- your turn: the cue pops (UI_STYLE section 7)
		-- GUI lane (step 13): YOUR TURN! slams in with a green glow.
		UIAnim.slam(self.turnTitle, HudParts.tone("Green"))
	end
	local gap = S.HeaderGap
	local height = S.TurnPopupTitleSize + gap
	local wordWidth = self.turnTitle.TextBounds.X
	local width = wordWidth + height + gap * 2
	self.turnGroup.Size = UDim2.fromOffset(width, height)
	self.turnGroup.Position = UDim2.new(0.5, 0, 0, (self.popupTop or self.headerBottom or 0) + gap)
	self.turnScale.Scale = K.Motion.PopFromScale
		+ (1 - K.Motion.PopFromScale) * UIAnim.backOut(elapsed / K.Motion.PopSeconds)
	local fade = 1 - math.clamp(left / S.TurnPopupFadeSeconds, 0, 1)
	HudParts.setTextTransparency(self.turnTitle, fade)
	self.turnIcon.ImageTransparency = fade
	-- The group's ball, where the icon would be; it goes as the words fade.
	self.turnBall.root.Visible = self.turnIsGroup and fade < 0.6
	HudParts.sizeBall(self.turnBall, height)
	self.turnBall.root.Position = UDim2.fromOffset(0, 0)
	-- The icon sits just left of the words, the pair centred.
	self.turnIcon.AnchorPoint = Vector2.new(0, 0.5)
	self.turnIcon.Position = UDim2.fromOffset(0, height / 2)
	self.turnIcon.Size = UDim2.fromOffset(height, height)
	self.turnTitle.Position = UDim2.fromOffset(height + gap, 0)
	self.turnTitle.Size = UDim2.new(1, -(height + gap), 1, 0)
	self.turnTitle.TextXAlignment = Enum.TextXAlignment.Left
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
	self.foulGroup.Position = UDim2.new(0.5, 0, 0, (self.popupTop or self.headerBottom or 0) + gap)
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
	-- The coin flip only: the end of a match is the result screen (ResultScreen, from the
	-- server's MatchSummary), the same screen for every player (designer, 2026-09-27).
	self.overlay.Visible = phase == "CoinFlip"
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
	self.presentationText.Visible = not coinPhase
	self.resultIcon.Visible = not coinPhase
	if coinPhase and snapshot.coin then
		self.rays.Visible = false
		local coin = snapshot.coin
		-- A few words at a time (designer, 2026-09-27): your side on the still coin, the same
		-- while it spins, then who breaks once it lands, for the rest of the card's time.
		local seated = Engine.seat(snapshot, self.localUserId) ~= nil
		local ourSideHeads = coin.headsTeam == self.ours
		local progressCoin = math.clamp((elapsed - S.CoinHoldSeconds) / S.CoinSpinSeconds, 0, 1)
		local turn = (1 - (1 - progressCoin) ^ 3) * math.pi * 8
		local landed = progressCoin >= 1
		local heads = if landed
			then coin.winnerTeam == coin.headsTeam
			elseif elapsed < S.CoinHoldSeconds and seated then ourSideHeads
			else math.cos(turn) >= 0
		self.coin.Size =
			UDim2.fromOffset(S.CoinSize * math.max(0.08, math.abs(math.cos(turn))), S.CoinSize)
		self.coin.Rotation = math.sin(turn / 2) * 12 * (1 - progressCoin)
		self.coinGlyph.Text = if heads then Copy.CoinHeadGlyph else Copy.CoinTailGlyph
		self.presentationTitle.Text = if landed
			then (if coin.breaker == self.localUserId
				then Copy.CoinYouBreak
				else string.format(
					Copy.CoinBreaks,
					string.upper(nameFor(snapshot, coin.breaker))
				))
			elseif seated then (if ourSideHeads
				then Copy.CoinYouAre.Heads
				else Copy.CoinYouAre.Tails)
			else Copy.CoinTitle
		self.presentationTitle.TextColor3 = tone("Gold")
	end
end

function MatchHUD.destroy(self: any)
	self.alive = false
	self:closeModal()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	for _, team in self.teams do
		for _, portrait in team.portraits do
			for _, connection in portrait.rankConnections do
				connection:Disconnect()
			end
		end
	end
	self.root:Destroy() -- the portraits' rank badges leave the shared clock with it
	local probe = self.topbarRoom and self.topbarRoom.Parent
	if probe then
		probe:Destroy()
	end
end

return MatchHUD
