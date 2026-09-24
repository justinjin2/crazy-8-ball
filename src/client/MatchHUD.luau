--!strict
-- Match-only presentation. Every deadline and outcome comes from the server snapshot.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Copy = Strings.Match
local S = Config.Multiplayer.Style
local MatchHUD = {}
MatchHUD.__index = MatchHUD

-- The cue-ball arrows, which repeat while held.
local PLACE_KEYS = { "PlaceLeft", "PlaceRight", "PlaceUp", "PlaceDown" }

local function color(values: { number }): Color3
	return Color3.fromRGB(values[1], values[2], values[3])
end

local function frame(parent: Instance, name: string): Frame
	local object = Instance.new("Frame")
	object.Name = name
	object.BorderSizePixel = 0
	object.BackgroundTransparency = 1
	object.Parent = parent
	return object
end

local function corner(parent: Instance, radius: number)
	local object = Instance.new("UICorner")
	object.CornerRadius = UDim.new(0, radius)
	object.Parent = parent
end

local function outline(parent: Instance, tint: Color3, thickness: number): UIStroke
	local object = Instance.new("UIStroke")
	object.Color = tint
	object.Thickness = thickness
	object.Transparency = 0.3
	object.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	object.Parent = parent
	return object
end

local function label(parent: Instance, name: string, size: number, text: string): TextLabel
	local object = Instance.new("TextLabel")
	object.Name = name
	object.BackgroundTransparency = 1
	object.Font = Enum.Font.GothamMedium
	object.TextSize = size
	object.TextColor3 = color(S.Text)
	object.Text = text
	object.TextTruncate = Enum.TextTruncate.AtEnd
	object.Parent = parent
	return object
end

local function panel(parent: Instance, name: string): Frame
	local object = frame(parent, name)
	object.BackgroundTransparency = 0.06
	object.BackgroundColor3 = color(S.Panel)
	corner(object, S.Radius)
	outline(object, color(S.Border), 1)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(color(S.PanelTop), color(S.Panel))
	gradient.Rotation = 90
	gradient.Parent = object
	return object
end

local function button(parent: Instance, text: string, action: () -> ()): TextButton
	local object = Instance.new("TextButton")
	object.BackgroundColor3 = color(S.PanelTop)
	object.BorderSizePixel = 0
	object.AutoButtonColor = false
	object.Font = Enum.Font.GothamBold
	object.TextSize = S.StatusSize
	object.TextColor3 = color(S.Text)
	object.Text = text
	object.Selectable = true
	object.Parent = parent
	corner(object, S.Radius / 2)
	local border = outline(object, color(S.Border), 1)
	local pressScale = Instance.new("UIScale")
	pressScale.Parent = object
	local pressTween: Tween? = nil
	local function pressed(down: boolean)
		if pressTween then
			pressTween:Cancel()
		end
		local nextTween = TweenService:Create(
			pressScale,
			TweenInfo.new(S.QuickMotion),
			{ Scale = if down then S.PressedScale else 1 }
		)
		pressTween = nextTween
		nextTween:Play()
	end
	object.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
			or input.KeyCode == Enum.KeyCode.ButtonA
		then
			pressed(true)
		end
	end)
	object.InputEnded:Connect(function()
		pressed(false)
	end)
	object.MouseLeave:Connect(function()
		pressed(false)
	end)
	local running: Tween? = nil
	local function highlight(selected: boolean)
		if running then
			running:Cancel()
		end
		local nextTween = TweenService:Create(border, TweenInfo.new(S.QuickMotion), {
			Color = color(if selected then S.Selected else S.Border),
			Transparency = if selected then 0 else 0.3,
		})
		running = nextTween
		nextTween:Play()
	end
	object.MouseEnter:Connect(function()
		highlight(true)
	end)
	object.MouseLeave:Connect(function()
		highlight(false)
	end)
	object.SelectionGained:Connect(function()
		highlight(true)
	end)
	object.SelectionLost:Connect(function()
		highlight(false)
	end)
	object.Activated:Connect(action)
	return object
end

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

local function makePortrait(parent: Instance): any
	local root = frame(parent, "Player")
	local imageFrame = frame(root, "PortraitFrame")
	imageFrame.BackgroundTransparency = 0
	imageFrame.BackgroundColor3 = color(S.Disabled)
	corner(imageFrame, S.Radius / 2)
	local border = outline(imageFrame, color(S.Border), 1)
	local fallback = label(imageFrame, "Fallback", S.StatusSize, Copy.AvatarFallback)
	fallback.Size = UDim2.fromScale(1, 1)
	local avatar = Instance.new("ImageLabel")
	avatar.Name = "Avatar"
	avatar.BackgroundTransparency = 1
	avatar.ScaleType = Enum.ScaleType.Fit
	avatar.Size = UDim2.fromScale(1, 1)
	avatar.Parent = imageFrame
	corner(avatar, S.Radius / 2)
	local name = label(root, "Name", S.NameSize, "")
	name.TextColor3 = color(S.Muted)
	local active = frame(imageFrame, "ActiveMarker")
	active.AnchorPoint = Vector2.new(1, 1)
	active.Position = UDim2.fromScale(1, 1)
	active.Size = UDim2.fromOffset(S.PortraitSize / 5, S.PortraitSize / 5)
	active.BackgroundTransparency = 0
	active.BackgroundColor3 = color(S.Active)
	corner(active, S.PortraitSize)
	outline(active, color(S.Panel), 2)
	local perimeter = {}
	for i = 1, 4 do
		local edge = frame(imageFrame, "ClockEdge" .. i)
		edge.BackgroundTransparency = 0
		edge.BackgroundColor3 = color(S.Active)
		edge.ZIndex = 3
		table.insert(perimeter, edge)
	end
	return {
		root = root,
		imageFrame = imageFrame,
		image = avatar,
		fallback = fallback,
		name = name,
		active = active,
		border = border,
		edges = perimeter,
		userId = nil,
		occupied = false,
	}
end

local function makeBall(parent: Instance): any
	local root = frame(parent, "BallSlot")
	local sphere = frame(root, "Ball")
	sphere.Size = UDim2.fromScale(1, 1)
	sphere.BackgroundTransparency = 0
	sphere.ClipsDescendants = true
	corner(sphere, S.BallSize)
	local border = outline(sphere, color(S.Text), 1)
	border.Transparency = 0.65
	local stripe = frame(sphere, "Stripe")
	stripe.Position = UDim2.fromScale(0, 0.24)
	stripe.Size = UDim2.fromScale(1, 0.52)
	stripe.BackgroundTransparency = 0
	local face = frame(sphere, "NumberDisc")
	face.AnchorPoint = Vector2.new(0.5, 0.5)
	face.Position = UDim2.fromScale(0.5, 0.5)
	face.Size = UDim2.fromScale(0.53, 0.53)
	face.BackgroundTransparency = 0
	face.BackgroundColor3 = color(S.Text)
	corner(face, S.BallSize)
	local number = label(face, "Number", S.NameSize, "")
	number.Size = UDim2.fromScale(1, 1)
	number.Font = Enum.Font.GothamBold
	number.TextColor3 = color(S.Panel)
	-- A red X across the whole ball, drawn as two crossed bars. It hangs off the slot rather
	-- than the round Ball frame, which clips, so the bars can run past the rim; the slot's
	-- UIScale pops it with the ball. Bar sizes follow the ball size in layout.
	local cross = frame(root, "Pocketed")
	cross.AnchorPoint = Vector2.new(0.5, 0.5)
	cross.Position = UDim2.fromScale(0.5, 0.5)
	cross.Size = UDim2.fromScale(1, 1)
	cross.ZIndex = 4
	cross.Visible = false
	local bars = {}
	for _, angle in { 45, -45 } do
		local bar = frame(cross, "Bar")
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Rotation = angle
		bar.BackgroundTransparency = 0
		bar.BackgroundColor3 = color(S.PocketedMark)
		bar.ZIndex = 4
		outline(bar, color(S.Panel), S.PocketedMarkStrokePx)
		table.insert(bars, bar)
	end
	local scale = Instance.new("UIScale")
	scale.Parent = root
	return {
		root = root,
		sphere = sphere,
		stripe = stripe,
		face = face,
		number = number,
		cross = cross,
		bars = bars,
		scale = scale,
		border = border,
		down = false,
		changedAt = 0,
	}
end

-- Draw a numbered slot as ball `id`: its own colours, or grey with the red X once it is
-- down. The 8 is dimmed while locked and outlined green once it is ready.
local function paintBall(ball: any, id: number, down: boolean, ready: boolean)
	ball.number.Text = tostring(id)
	ball.stripe.Visible = id > 8
	local tint = color(Config.Balls.Colors[if id > 8 then id - 8 else id])
	ball.sphere.BackgroundColor3 = if down
		then color(S.Disabled)
		elseif id > 8 then color(S.Text)
		else tint
	ball.stripe.BackgroundColor3 = if down then color(S.Disabled) else tint
	ball.face.BackgroundColor3 = if down then color(S.Muted) else color(S.Text)
	ball.cross.Visible = down
	ball.border.Color = color(if id == 8 and ready then S.Active else S.Text)
	ball.border.Transparency = if id == 8 and ready then 0 else 0.65
	ball.sphere.BackgroundTransparency = if id == 8 and not ready then 0.5 else 0
end

-- Size a full numbered slot: the ball, its number and the red X bars.
local function sizeBall(ball: any, size: number)
	ball.root.Size = UDim2.fromOffset(size, size)
	ball.number.TextSize = math.max(S.NameSize, size * 0.39)
	local length = math.floor(size * S.PocketedMarkLength + 0.5)
	local thick = math.max(S.PocketedMarkMinPx, math.floor(size * S.PocketedMarkThickness + 0.5))
	for _, bar in ball.bars do
		bar.Size = UDim2.fromOffset(length, thick)
	end
end

-- The OPEN TABLE label over a team's ball area, with the balls already down beside it.
local function layoutOpen(
	team: any,
	ballLeft: number,
	ballTop: number,
	ballsWidth: number,
	rowsHeight: number,
	ballRows: number
)
	team.open.Position = UDim2.fromOffset(ballLeft, ballTop)
	team.open.Size = UDim2.fromOffset(ballsWidth, rowsHeight)
	team.open.TextSize = S.StatusSize
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
		team.open.TextSize = S.NameSize
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
				ball.root.Size = UDim2.fromOffset(size, size)
				ball.number.TextSize = math.max(S.OpenBallMinText, size * 0.45)
				local length = math.floor(size * S.PocketedMarkLength + 0.5)
				local thick = math.max(
					S.PocketedMarkMinPx - 1,
					math.floor(size * S.PocketedMarkThickness + 0.5)
				)
				for _, bar in ball.bars do
					bar.Size = UDim2.fromOffset(length, thick)
				end
				n += 1
			end
		end
	end
end

local function makeTeam(parent: Instance, name: string): any
	local root = panel(parent, name)
	local title = label(root, "TeamName", S.NameSize, "")
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = color(S.Muted)
	local group = label(root, "Group", S.NameSize, Copy.OpenTable)
	group.TextXAlignment = Enum.TextXAlignment.Right
	group.TextColor3 = color(S.Muted)
	local portraits, balls = {}, {}
	for _ = 1, 3 do
		table.insert(portraits, makePortrait(root))
	end
	for _ = 1, 8 do
		table.insert(balls, makeBall(root))
	end
	local open = label(root, "OpenTable", S.StatusSize, Copy.OpenTable)
	open.TextColor3 = color(S.Muted)
	-- While the table is open nobody owns a group yet, but balls can already be down (the
	-- break). They show here, small and crossed out in their own colours, until the groups
	-- are decided. The 8 is left out: on the break it is always re-spotted.
	local openRow = frame(root, "OpenPocketed")
	local openBalls = {}
	for id = 1, 15 do
		if id ~= 8 then
			local ball = makeBall(openRow)
			ball.id = id
			table.insert(openBalls, ball)
		end
	end
	return {
		root = root,
		title = title,
		group = group,
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
	self.localUserId = Players.LocalPlayer.UserId
	self.lastNow = workspace:GetServerTimeNow()
	self.connections = {}
	self.alive = true
	self.precisionOpen = false
	-- Ball in hand, from Main: whether the local shooter may move the cue ball now, and
	-- whether it just failed to follow the pointer.
	self.placing = false
	self.placingBlocked = false
	-- The placement arrow being held down: its step and when it next repeats.
	self.held = nil
	self.pressHandled = {}
	self.setupStacked = false
	self.invalidTarget = false
	self.modalMode = nil
	self.respondedVote = nil
	self.width = 0
	self.avatarCache = {}
	-- Which balls were down in the last snapshot, by id, so a ball pops when IT goes down
	-- rather than when a slot's contents change (the rows remap when colors are revealed).
	self.downIds = {}
	self.root = frame(screen, "MultiplayerHUD")
	self.root.ZIndex = 2 -- setup targets are a lower sibling; dialogs always cover them
	self.root.Size = UDim2.fromScale(1, 1)
	self.root.Visible = false
	self.teams = { makeTeam(self.root, "LocalTeam"), makeTeam(self.root, "OtherTeam") }
	-- Solo: fifteen slots on the local panel in playing order (first group, other group, 8).
	self.teams[1].soloBalls, self.teams[2].soloBalls = {}, {}
	for _ = 1, 15 do
		table.insert(self.teams[1].soloBalls, makeBall(self.teams[1].root))
	end
	-- The Play Solo offer, under the header while this player waits alone at the table.
	self.soloOffer = panel(self.root, "PlaySolo")
	self.soloOffer.AnchorPoint = Vector2.new(0.5, 0)
	self.soloOffer.Visible = false
	self.soloHint = label(self.soloOffer, "Hint", S.NameSize, Copy.SoloHint)
	self.soloHint.TextColor3 = color(S.Muted)
	self.soloSentAt = -math.huge
	self.soloButton = button(self.soloOffer, Copy.PlaySolo, function()
		if self:soloAvailable() then
			self.soloSentAt = self.lastNow -- hidden until the server answers
			onAction("StartSolo", nil)
		end
	end)
	self.soloButton.BackgroundColor3 = color(S.Active)
	self.soloButton.TextColor3 = color(S.Panel)
	self.center = panel(self.root, "MatchStatus")
	self.status = label(self.center, "Status", S.StatusSize, "")
	self.status.Font = Enum.Font.GothamBold
	self.clock = label(self.center, "Timer", S.TimerSize, "")
	self.clock.Font = Enum.Font.RobotoMono
	self.clockScale = Instance.new("UIScale")
	self.clockScale.Parent = self.clock
	self.detail = label(self.center, "Detail", S.NameSize, "")
	self.detail.TextColor3 = color(S.Muted)
	self.leave = button(self.center, Copy.Leave, function()
		self:openLeave()
	end)
	self.setup = panel(self.root, "Setup")
	self.setup.AnchorPoint = Vector2.new(0.5, 1)
	-- One line of instruction while the cue ball is in hand. There is nothing to confirm:
	-- the ball stays where it is left, and the shot can be taken at any time.
	self.setupLabel = label(self.setup, "Instruction", S.StatusSize, "")
	self.setupLabel.TextScaled = true
	self.setupSize = Instance.new("UITextSizeConstraint")
	self.setupSize.Parent = self.setupLabel
	-- The foul card: the rule that was broken, as one plain "you must" line. It is for people
	-- who do not know the rules, so it stays up a few seconds past the short Foul phase and
	-- never takes input (the next shooter can already place and aim underneath it).
	-- A plain Frame, faded by hand: a CanvasGroup can fail to draw on low-memory phones.
	self.foulGroup = frame(self.root, "FoulCard")
	self.foulGroup.AnchorPoint = Vector2.new(0.5, 0)
	self.foulGroup.Visible = false
	local foulPanel = panel(self.foulGroup, "Card")
	foulPanel.Size = UDim2.fromScale(1, 1)
	self.foulPanel = foulPanel
	self.foulPanelTransparency = foulPanel.BackgroundTransparency
	self.foulStroke = outline(foulPanel, color(S.Danger), S.FoulCardStrokePx)
	self.foulTitle = label(foulPanel, "Title", S.StatusSize, "")
	self.foulTitle.Font = Enum.Font.GothamBold
	self.foulTitle.TextColor3 = color(S.Danger)
	self.foulReason = label(foulPanel, "Reason", S.StatusSize, "")
	self.foulReason.TextWrapped = true
	self.foulReason.TextTruncate = Enum.TextTruncate.None
	self.foulKey = ""
	self.foulUntil = 0
	self.invalid = label(self.root, "InvalidTarget", S.StatusSize, Copy.InvalidTarget)
	self.invalid.AnchorPoint = Vector2.new(0.5, 1)
	self.invalid.TextColor3 = color(S.Danger)
	self.invalid.Font = Enum.Font.GothamBold
	self.precisionButton = button(self.root, Copy.Precision, function()
		self:togglePrecision()
	end)
	self.precisionButton.AnchorPoint = Vector2.new(1, 1)
	self.precision = panel(self.root, "PrecisionControls")
	self.precision.AnchorPoint = Vector2.new(1, 1)
	self.precisionButtons = {}
	local function precision(key: string, text: string, kind: string, value: any)
		self.precisionButtons[key] = button(self.precision, text, function()
			onAction(kind, value)
		end)
	end
	precision("AimLeft", Copy.AimLeft, "PrecisionAim", -S.PrecisionAngleDegrees)
	precision("AimRight", Copy.AimRight, "PrecisionAim", S.PrecisionAngleDegrees)
	precision("PowerDown", Copy.PowerDown, "PrecisionPower", -S.PrecisionPowerStep)
	precision("PowerUp", Copy.PowerUp, "PrecisionPower", S.PrecisionPowerStep)
	precision("Shoot", Copy.Shoot, "PrecisionShoot", nil)
	precision("Close", Copy.PrecisionCloseShort, "ClosePrecision", nil)
	-- The arrows move the cue ball relative to the screen ({sx, sy}: +x right, +y up) and
	-- repeat while held. A pointer or gamepad press steps on InputBegan; Activated covers a
	-- gamepad A that never reaches InputBegan, and is skipped when InputBegan already stepped.
	local function arrow(key: string, text: string, value: any)
		local object = button(self.precision, text, function()
			if self.pressHandled[key] then
				self.pressHandled[key] = nil
				return
			end
			onAction("PrecisionPlace", value)
		end)
		self.precisionButtons[key] = object
		object.InputBegan:Connect(function(input: InputObject)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
				or input.KeyCode == Enum.KeyCode.ButtonA
			then
				self.pressHandled[key] = true
				self.held = {
					key = key,
					value = value,
					input = input,
					nextAt = self.lastNow + S.PlacementRepeatDelay,
				}
				onAction("PrecisionPlace", value)
			end
		end)
		object.InputEnded:Connect(function(input: InputObject)
			local held = self.held
			if
				held
				and held.key == key
				and (input == held.input or input.KeyCode == Enum.KeyCode.ButtonA)
			then
				self.held = nil
			end
		end)
		object.MouseLeave:Connect(function()
			if self.held and self.held.key == key then
				self.held = nil
			end
			self.pressHandled[key] = nil -- no Activated follows a press dragged off the button
		end)
	end
	arrow("PlaceLeft", Copy.PlaceLeft, { sx = -1, sy = 0 })
	arrow("PlaceRight", Copy.PlaceRight, { sx = 1, sy = 0 })
	arrow("PlaceUp", Copy.PlaceUp, { sx = 0, sy = 1 })
	arrow("PlaceDown", Copy.PlaceDown, { sx = 0, sy = -1 })
	self.modal = Instance.new("TextButton")
	self.modal.Name = "ConfirmationBackdrop"
	self.modal.Size = UDim2.fromScale(1, 1)
	self.modal.BackgroundColor3 = color(S.Panel)
	self.modal.BackgroundTransparency = 1 - S.ModalDim
	self.modal.AutoButtonColor = false
	self.modal.Text = ""
	self.modal.Active = true
	self.modal.Modal = true
	self.modal.Selectable = false
	self.modal.Visible = false
	self.modal.ZIndex = 20
	self.modal.Parent = self.root
	self.dialog = panel(self.modal, "Dialog")
	self.modalTweens = {}
	self.dialogScale = Instance.new("UIScale")
	self.dialogScale.Parent = self.dialog
	self.dialog.ZIndex = 21
	self.dialog.AnchorPoint = Vector2.new(0.5, 0.5)
	self.dialog.Position = UDim2.fromScale(0.5, 0.5)
	self.dialogTitle = label(self.dialog, "Title", S.StatusSize + 4, "")
	self.dialogTitle.TextWrapped = true
	self.dialogTitle.TextTruncate = Enum.TextTruncate.None
	self.dialogTitle.Font = Enum.Font.GothamBold
	self.dialogBody = label(self.dialog, "Explanation", S.StatusSize, "")
	self.dialogBody.TextWrapped = true
	self.dialogBody.TextTruncate = Enum.TextTruncate.None
	self.dialogBody.TextColor3 = color(S.Muted)
	self.voteProgress = label(self.dialog, "VoteStatus", S.StatusSize, "")
	self.voteProgress.TextColor3 = color(S.Active)
	self.yes = button(self.dialog, Copy.Yes, function()
		local mode = self.modalMode
		self:closeModal()
		if mode == "Vote" then
			self.respondedVote = self:voteKey()
			onAction("Vote", true)
		elseif mode == "Queue" then
			onAction("LeaveQueue", nil)
		else
			onAction("Surrender", nil)
		end
	end)
	self.no = button(self.dialog, Copy.No, function()
		local mode = self.modalMode
		self:closeModal()
		if mode == "Vote" then
			self.respondedVote = self:voteKey()
			onAction("Vote", false)
		end
	end)
	self.yes.BackgroundColor3 = color(S.Danger)
	self.no.BackgroundColor3 = color(S.PanelTop)
	for _, object in self.dialog:GetDescendants() do
		if object:IsA("GuiObject") then
			object.ZIndex = 22
		end
	end
	self.overlay = Instance.new("CanvasGroup")
	self.overlay.Name = "MatchPresentation"
	self.overlay.Size = UDim2.fromScale(1, 1)
	self.overlay.BackgroundColor3 = color(S.Panel)
	self.overlay.BackgroundTransparency = 1 - S.ModalDim
	self.overlay.ZIndex = 10
	self.overlay.Visible = false
	self.overlay.Parent = self.root
	self.presentation = panel(self.overlay, "Presentation")
	self.presentationScale = Instance.new("UIScale")
	self.presentationScale.Parent = self.presentation
	self.presentation.AnchorPoint = Vector2.new(0.5, 0.5)
	self.presentation.Position = UDim2.fromScale(0.5, 0.5)
	self.presentationTitle = label(self.presentation, "Heading", S.TimerSize, "")
	self.presentationTitle.Font = Enum.Font.GothamBold
	self.presentationText = label(self.presentation, "Explanation", S.StatusSize, "")
	self.presentationText.TextWrapped = true
	self.presentationText.TextTruncate = Enum.TextTruncate.None
	self.coin = frame(self.presentation, "Coin")
	self.coin.AnchorPoint = Vector2.new(0.5, 0.5)
	self.coin.BackgroundColor3 = color(S.Gold)
	self.coin.BackgroundTransparency = 0
	corner(self.coin, S.ModalWidth)
	outline(self.coin, color(S.Text), 2)
	self.coinGlyph = label(self.coin, "Face", S.TimerSize, Copy.CoinHeadGlyph)
	self.coinGlyph.Size = UDim2.fromScale(1, 1)
	self.coinGlyph.TextColor3 = color(S.Panel)
	self.coinGlyph.Font = Enum.Font.GothamBlack
	self.coinOwner = label(self.presentation, "Sides", S.NameSize, "")
	self.coinOwner.TextColor3 = color(S.Muted)
	for _, object in self.presentation:GetDescendants() do
		if object:IsA("GuiObject") then
			object.ZIndex = 11
		end
	end
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
	local margin, gap = S.HeaderMargin, S.HeaderGap
	local short = self.root.AbsoluteSize.Y < S.ShortHeight
	local count = if self.snapshot then self.snapshot.teamSize else 3
	local portraitSize = S.PortraitSize
	local portraitsWidth = portraitSize * count + S.PortraitGap * (count - 1)
	local ballsWidth = S.BallSize * 8 + S.BallGap * 7
	local centerWidth = S.HeaderCenterWidth
	local availableWidth = width - margin * 2
	local columns = if (portraitsWidth + ballsWidth + gap * 3) * 2 + centerWidth + gap * 2
			<= availableWidth
		then 8
		else 4
	local ballSize = if columns == 8 then S.BallSize else S.ShortBallSize
	ballsWidth = ballSize * columns + S.BallGap * (columns - 1)
	local desiredTeamWidth = portraitsWidth + ballsWidth + gap * 3
	local desiredWidth = desiredTeamWidth * 2 + centerWidth + gap * 2
	local inline = desiredWidth <= availableWidth
	local teamWidth = if inline then desiredTeamWidth else (availableWidth - gap) / 2
	local ballRows = 8 / columns
	local headerHeight = if inline
		then math.max(S.HeaderHeight, ballSize * ballRows + S.BallGap * (ballRows - 1) + gap)
		else portraitSize + S.NameSize + gap * 2 + ballSize * ballRows + S.BallGap * (ballRows - 1)
	local besideMenu = inline and desiredWidth <= width - S.HeaderMenuLeft - S.HeaderMenuRight
	local top = S.HeaderTop - (if besideMenu then GuiService:GetGuiInset().Y else 0)
	local startX = if besideMenu
		then S.HeaderMenuLeft + (width - S.HeaderMenuLeft - S.HeaderMenuRight - desiredWidth) / 2
		else (width - (if inline then desiredWidth else availableWidth)) / 2
	self.headerBottom = top + headerHeight + (if inline then 0 else S.HeaderHeight + gap)
	for i, team in self.teams do
		local x = startX
			+ (if i == 1 then 0 else teamWidth + gap + (if inline then centerWidth + gap else 0))
		team.root.Position = UDim2.fromOffset(x, top)
		team.root.Size = UDim2.fromOffset(teamWidth, headerHeight)
		-- Ownership is shown by the numbered balls; avoid redundant rows of headings.
		team.title.Visible = false
		team.group.Visible = false
		local portraitLeft = if i == 1 then gap else teamWidth - portraitsWidth - gap
		for n, portrait in team.portraits do
			portrait.root.Position =
				UDim2.fromOffset(portraitLeft + (n - 1) * (portraitSize + S.PortraitGap), gap / 2)
			portrait.root.Size = UDim2.fromOffset(portraitSize, portraitSize + S.NameSize + gap / 2)
			portrait.imageFrame.Size = UDim2.fromOffset(portraitSize, portraitSize)
			portrait.name.Position = UDim2.fromOffset(-gap / 2, portraitSize + gap / 4)
			portrait.name.Size = UDim2.fromOffset(portraitSize + gap, S.NameSize + gap / 2)
			portrait.root.Visible = n <= count and portrait.occupied
		end
		local ballLeft = if inline
			then (if i == 1 then portraitsWidth + gap * 2 else gap)
			else (teamWidth - ballsWidth) / 2
		local ballTop = if inline
			then (headerHeight - ballSize * ballRows - S.BallGap * (ballRows - 1)) / 2
			else portraitSize + S.NameSize + gap
		for n, ball in team.balls do
			local column, row = (n - 1) % columns, math.floor((n - 1) / columns)
			ball.root.Position = UDim2.fromOffset(
				ballLeft + column * (ballSize + S.BallGap),
				ballTop + row * (ballSize + S.BallGap)
			)
			sizeBall(ball, ballSize)
		end
		local rowsHeight = ballSize * ballRows + S.BallGap * (ballRows - 1)
		layoutOpen(team, ballLeft, ballTop, ballsWidth, rowsHeight, ballRows)
	end
	self.center.Position = UDim2.fromOffset(
		if inline then startX + teamWidth + gap else (width - centerWidth) / 2,
		top + (if inline then 0 else headerHeight + gap)
	)
	self.center.Size = UDim2.fromOffset(centerWidth, S.HeaderHeight)
	if self.snapshot and self.snapshot.solo then
		self:layoutSolo(width)
	end
	-- The Play Solo offer hangs under the header (only while waiting, so never over play).
	self.soloOffer.Position = UDim2.new(0.5, 0, 0, self.headerBottom + gap)
	self.soloOffer.Size = UDim2.fromOffset(
		math.min(S.SoloPanelWidth, availableWidth),
		S.NameSize + S.ButtonHeight + gap * 2
	)
	self.soloHint.Position = UDim2.fromOffset(gap, gap / 2)
	self.soloHint.Size = UDim2.new(1, -gap * 2, 0, S.NameSize + gap / 2)
	self.soloButton.Position = UDim2.new(0, gap, 1, -S.ButtonHeight - gap)
	self.soloButton.Size = UDim2.new(1, -gap * 2, 0, S.ButtonHeight)
	local leaveWidth = S.ButtonHeight * 1.4
	local contentWidth = centerWidth - leaveWidth - gap * 2
	self.status.Position = UDim2.fromOffset(gap / 2, gap / 2)
	self.status.Size = UDim2.fromOffset(contentWidth, S.NameSize + gap / 2)
	self.status.TextSize = S.NameSize
	self.clock.Position = UDim2.fromOffset(gap / 2, S.NameSize + gap / 2)
	self.clock.Size = UDim2.fromOffset(contentWidth, S.HeaderTimerSize)
	self.clock.TextSize = S.HeaderTimerSize
	self.detail.Position = UDim2.fromOffset(gap / 2, S.NameSize + gap / 2 + S.HeaderTimerSize)
	self.detail.Size = UDim2.fromOffset(contentWidth, S.NameSize)
	self.detail.TextSize = S.NameSize
	self.detail.Visible = true
	self.leave.Position = UDim2.new(1, -leaveWidth - gap / 2, 0.5, -S.ButtonHeight / 2)
	self.leave.Size = UDim2.fromOffset(leaveWidth, S.ButtonHeight)
	self.leave.TextSize = S.NameSize
	self.leave.TextWrapped = true
	-- The placement instruction: one line centred at the bottom, clear of the fine-controls
	-- button in the corner, or stacked above it when the screen is too narrow for both.
	local precisionWidth = S.ButtonHeight * 2.6
	local setupHeight = if short then S.ShortSetupHeight else S.SetupHeight
	local setupWidth = math.min(S.ModalWidth, width - 2 * (margin + precisionWidth + gap))
	self.setupStacked = setupWidth < S.SetupMinWidth
	if self.setupStacked then
		setupWidth = math.min(S.ModalWidth, width - margin * 2)
	end
	self.setup.Position =
		UDim2.new(0.5, 0, 1, -(margin + (if self.setupStacked then S.ButtonHeight + gap else 0)))
	self.setup.Size = UDim2.fromOffset(setupWidth, setupHeight)
	self.setupHeight = setupHeight
	self.setupLabel.Position = UDim2.fromOffset(gap, gap / 4)
	self.setupLabel.Size = UDim2.new(1, -gap * 2, 1, -gap / 2)
	self.setupSize.MaxTextSize = if short then S.NameSize else S.StatusSize
	self.invalid.Size = UDim2.new(1, -margin * 2, 0, S.StatusSize + gap)
	self.precisionButton.Position = UDim2.new(1, -margin, 1, -margin)
	self.precisionButton.Size = UDim2.fromOffset(precisionWidth, S.ButtonHeight)
	self.precisionButton.Text = if self.precisionOpen then Copy.PrecisionClose else Copy.Precision
	local keys = { "AimLeft", "AimRight", "PowerDown", "PowerUp", "Shoot", "Close" }
	if self.placing then
		keys = if self.snapshot and self.snapshot.breakShot
			then { "PlaceLeft", "PlaceRight", "AimLeft", "AimRight", "Shoot", "Close" }
			else {
				"PlaceLeft",
				"PlaceRight",
				"PlaceUp",
				"PlaceDown",
				"AimLeft",
				"AimRight",
				"Shoot",
				"Close",
			}
	end
	local maxCols = math.max(1, math.floor((width - margin * 2 - gap) / (S.ButtonHeight + gap)))
	local cols = math.min(if short then #keys elseif #keys > 6 then 4 else 3, maxCols)
	local buttonWidth =
		math.min(S.ButtonHeight * 1.6, (width - margin * 2 - gap * (cols + 1)) / cols)
	local rows = math.ceil(#keys / cols)
	self.precision.Position = UDim2.new(1, -margin, 1, -margin)
	self.precision.Size =
		UDim2.fromOffset(buttonWidth * cols + gap * (cols + 1), (S.ButtonHeight + gap) * rows + gap)
	for _, item in self.precisionButtons do
		item.Visible = false
	end
	for index, key in keys do
		local item = self.precisionButtons[key]
		item.Visible = true
		item.Position = UDim2.fromOffset(
			gap + ((index - 1) % cols) * (buttonWidth + gap),
			gap + math.floor((index - 1) / cols) * (S.ButtonHeight + gap)
		)
		item.Size = UDim2.fromOffset(buttonWidth, S.ButtonHeight)
		item.TextSize = if short or buttonWidth < S.ButtonHeight * 1.6
			then S.NameSize
			else S.StatusSize
	end
	self.dialog.Size =
		UDim2.fromOffset(math.min(S.ModalWidth, width - margin * 2), S.ButtonHeight * 5 + gap * 3)
	self.dialogTitle.Position = UDim2.fromOffset(gap * 2, gap * 2)
	self.dialogTitle.Size = UDim2.new(1, -gap * 4, 0, S.ButtonHeight)
	self.dialogBody.Position = UDim2.fromOffset(gap * 2, S.ButtonHeight + gap * 2)
	self.dialogBody.Size = UDim2.new(1, -gap * 4, 0, S.ButtonHeight * 1.7)
	self.voteProgress.Position = UDim2.fromOffset(gap, S.ButtonHeight * 3 + gap)
	self.voteProgress.Size = UDim2.new(1, -gap * 2, 0, S.StatusSize + gap)
	self.no.Position = UDim2.new(0, gap * 2, 1, -S.ButtonHeight - gap * 2)
	self.no.Size = UDim2.new(0.5, -gap * 2.5, 0, S.ButtonHeight)
	self.yes.Position = UDim2.new(0.5, gap / 2, 1, -S.ButtonHeight - gap * 2)
	self.yes.Size = self.no.Size
	self.presentation.Size = UDim2.fromOffset(
		math.min(S.ModalWidth, width - margin * 2),
		if self.snapshot and self.snapshot.phase == "Result"
			then S.ResultPanelHeight
			else S.ButtonHeight * 5 + gap * 3
	)
	self.presentationTitle.Position = UDim2.fromOffset(gap, gap * 2)
	self.presentationTitle.Size = UDim2.new(1, -gap * 2, 0, S.ButtonHeight)
	self.coin.Position = UDim2.fromScale(0.5, 0.49)
	self.coinOwner.Position = UDim2.new(0, gap, 1, -S.ButtonHeight * 1.8)
	self.coinOwner.Size = UDim2.new(1, -gap * 2, 0, S.StatusSize + gap)
	self.presentationText.Position = UDim2.new(0, gap * 2, 1, -S.ButtonHeight - gap)
	self.presentationText.Size = UDim2.new(1, -gap * 4, 0, S.ButtonHeight)
end

-- Solo: the player's panel alone, one portrait then fifteen balls in playing order, beside
-- the status panel when it fits and above it otherwise. The row wraps (S.SoloWrapColumns and
-- the rest) when a single line of fifteen does not fit.
function MatchHUD.layoutSolo(self: any, width: number)
	local gap, portraitSize, centerWidth = S.HeaderGap, S.PortraitSize, S.HeaderCenterWidth
	local availableWidth = width - S.HeaderMargin * 2
	local function teamWidthFor(columns: number, size: number): number
		return portraitSize + size * columns + S.BallGap * (columns - 1) + gap * 3
	end
	-- The first arrangement that fits, beside the status panel (inline) or above it.
	local wrap = S.SoloWrapColumns
	local choice = { columns = wrap, size = S.ShortBallSize, inline = false }
	for _, option in
		{
			{ columns = 15, size = S.BallSize, inline = true },
			{ columns = wrap, size = S.BallSize, inline = true },
			{ columns = 15, size = S.BallSize, inline = false },
			{ columns = wrap, size = S.BallSize, inline = false },
		}
	do
		local beside = if option.inline then gap + centerWidth else 0
		if teamWidthFor(option.columns, option.size) + beside <= availableWidth then
			choice = option
			break
		end
	end
	local columns, ballSize, inline = choice.columns, choice.size, choice.inline
	local rows = math.ceil(15 / columns)
	local rowsHeight = ballSize * rows + S.BallGap * (rows - 1)
	local ballsWidth = ballSize * columns + S.BallGap * (columns - 1)
	local teamWidth = teamWidthFor(columns, ballSize)
	local headerHeight = math.max(S.HeaderHeight, rowsHeight + gap)
	local desiredWidth = teamWidth + (if inline then gap + centerWidth else 0)
	local besideMenu = inline and desiredWidth <= width - S.HeaderMenuLeft - S.HeaderMenuRight
	local top = S.HeaderTop - (if besideMenu then GuiService:GetGuiInset().Y else 0)
	local startX = if besideMenu
		then S.HeaderMenuLeft + (width - S.HeaderMenuLeft - S.HeaderMenuRight - desiredWidth) / 2
		else (width - desiredWidth) / 2
	self.headerBottom = top + headerHeight + (if inline then 0 else S.HeaderHeight + gap)
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
		sizeBall(ball, ballSize)
	end
	layoutOpen(team, ballLeft, ballTop, ballsWidth, rowsHeight, rows)
	self.center.Position = UDim2.fromOffset(
		if inline then startX + teamWidth + gap else (width - centerWidth) / 2,
		top + (if inline then 0 else headerHeight + gap)
	)
end

--- Whether the local player is waiting alone at this table, so Play Solo is on offer.
function MatchHUD.soloAvailable(self: any): boolean
	local snapshot = self.snapshot
	if not snapshot or snapshot.phase ~= "Waiting" or snapshot.solo then
		return false
	end
	local alone = false
	for _, seat in snapshot.seats do
		if seat.connected ~= false then
			if seat.userId ~= self.localUserId then
				return false
			end
			alone = true
		end
	end
	return alone
end

function MatchHUD.togglePrecision(self: any)
	self.precisionOpen = not self.precisionOpen
	if
		not self.precisionOpen
		and GuiService.SelectedObject
		and GuiService.SelectedObject:IsDescendantOf(self.precision)
	then
		GuiService.SelectedObject = nil
	end
	self:layout()
	self.onAction("PrecisionToggle", self.precisionOpen)
end

function MatchHUD.reservedHeight(self: any): number
	return self.headerBottom or S.HeaderHeight
end

function MatchHUD.reservedBottom(self: any): number
	if self.precision.Visible then
		return self.precision.AbsoluteSize.Y + S.HeaderMargin
	end
	local bottom = S.ButtonHeight -- the fine-controls button row
	if self.setup.Visible then
		local height = self.setupHeight or S.SetupHeight
		bottom = if self.setupStacked
			then S.ButtonHeight + S.HeaderGap + height
			else math.max(height, S.ButtonHeight)
	end
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
	self.dialogScale.Scale = S.PanelEntranceScale
	self.modalTweens = {
		TweenService:Create(
			self.modal,
			TweenInfo.new(S.Motion),
			{ BackgroundTransparency = 1 - S.ModalDim }
		),
		TweenService:Create(self.dialogScale, TweenInfo.new(S.Motion), { Scale = 1 }),
	}
	for _, tween in self.modalTweens do
		tween:Play()
	end
	self.oldSelection = GuiService.SelectedObject
	if mode == "Vote" then
		self.dialogTitle.Text = Copy.VoteTitle
		self.dialogBody.Text = Copy.VoteBody
	else
		self.dialogTitle.Text = Copy.LeaveQuestion
		self.dialogBody.Text = if mode == "Queue"
			then Copy.QueueWaiting
			elseif self.snapshot.solo then Copy.LeaveSoloGame
			elseif self.snapshot.teamSize > 1 then Copy.LeaveTeam
			else Copy.LeaveSolo
	end
	self.voteProgress.Text = if self.snapshot.solo then "" else Copy.ClocksContinue
	GuiService.SelectedObject = self.no
end

function MatchHUD.openLeave(self: any)
	local snapshot = self.snapshot
	if not snapshot or snapshot.phase == "Result" or self.modal.Visible then
		return
	end
	self:showModal(
		if snapshot.phase == "Waiting" or snapshot.phase == "Countdown" then "Queue" else "Leave"
	)
end

function MatchHUD.isModal(self: any): boolean
	return self.modal.Visible
end

--- Whether the local shooter may move the cue ball now, and whether it could not follow the
--- pointer. The arrows and the instruction follow it.
function MatchHUD.setPlacing(self: any, placing: boolean, blocked: boolean)
	self.placingBlocked = placing and blocked
	if placing == self.placing then
		return
	end
	self.placing = placing
	if not placing then
		self.held = nil
	end
	self:layout()
	local selected = GuiService.SelectedObject
	if not placing and selected then
		for _, key in PLACE_KEYS do
			if selected == self.precisionButtons[key] then
				GuiService.SelectedObject = self.precisionButtons.AimLeft
			end
		end
	end
end

function MatchHUD.setInvalidTarget(self: any, invalid: boolean)
	self.invalidTarget = invalid
end

function MatchHUD.setSnapshot(self: any, snapshot: any?, userId: number)
	local old = self.snapshot
	self.snapshot = snapshot
	self.localUserId = userId
	self.root.Visible = snapshot ~= nil
	if snapshot == nil then
		self:closeModal()
		self.precisionOpen = false
		self.placing, self.placingBlocked, self.held = false, false, nil
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
		self.foulUntil = snapshot.phaseStartedAt + S.FoulCardSeconds
		local explain = Copy.FoulExplain[foul.reason] or ""
		if foul.reason == "WrongContact" then
			local group = snapshot.groups and snapshot.groups[foul.team]
			explain = if group == nil
				then Copy.FoulExplain.WrongContactOpen
				elseif eligible(snapshot, foul.team) then Copy.FoulExplain.WrongContactEight
				else string.format(
					Copy.FoulExplain.WrongContactOwn,
					if group == "solids" then Copy.SolidsWord else Copy.StripesWord
				)
		end
		self.foulTitle.Text = if foul.by == userId
			then Copy.FoulYou
			else string.format(Copy.FoulTitle, nameFor(snapshot, foul.by))
		self.foulReason.Text = explain
	end
	for side, team in self.teams do
		local teamId = if side == 1 then ours else 3 - ours
		team.teamId = teamId
		team.title.Text = if side == 1 then Copy.YourTeam else Copy.OpponentTeam
		local group = snapshot.groups and snapshot.groups[teamId]
		local ready = eligible(snapshot, teamId)
		team.group.Text = if group == nil
			then ""
			elseif ready then Copy.EightReady
			elseif group == "solids" then Copy.Solids
			else Copy.Stripes
		team.group.TextColor3 = color(if ready then S.Active else S.Muted)
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
			ball.number.Text = tostring(ball.id)
			ball.stripe.Visible = ball.id > 8
			local tint = color(Config.Balls.Colors[if ball.id > 8 then ball.id - 8 else ball.id])
			ball.sphere.BackgroundColor3 = if ball.id > 8 then color(S.Text) else tint
			ball.stripe.BackgroundColor3 = tint
			ball.face.BackgroundColor3 = color(S.Text)
			ball.cross.Visible = true
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
			portrait.border.Color = color(if portrait.active.Visible then S.Active else S.Border)
			if seat then
				portrait.name.Text = if seat.connected == false
					then Copy.Disconnected
					else (if snapshot.teamSize > 1 and not snapshot.solo
						then string.format(
							Copy.MemberName,
							seat.slot,
							seat.displayName or seat.name
						)
						else seat.displayName or seat.name)
				portrait.name.TextColor3 =
					color(if portrait.active.Visible then S.Active else S.Muted)
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
							local ok, content, ready = pcall(function()
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
								and ready
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
			paintBall(ball, id, down, ready)
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
			paintBall(ball, id, down, soloReady)
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
	local thickness = 2
	local remaining = progress * 4
	for index, edge in portrait.edges do
		local fraction = math.clamp(remaining - (index - 1), 0, 1)
		edge.Visible = portrait.active.Visible and fraction > 0
		edge.BackgroundColor3 = color(if danger then S.Danger else S.Active)
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
	local shooterName = nameFor(snapshot, snapshot.shooter)
	self.status.Text = Copy.Phase[phase] or ""
	self.status.TextTransparency = 0
	self.status.TextColor3 = color(S.Text)
	self.detail.Text = if snapshot.solo
		then Copy.SoloMode
		elseif snapshot.shooter then string.format(Copy.PlayerTurn, shooterName)
		else string.format(Copy.Mode, snapshot.teamSize, snapshot.teamSize)
	if phase == "Intro" then
		self.status.Text = if isShooter then Copy.YourTurn else Copy.Phase.Intro
		self.status.TextColor3 = color(S.Active)
		local elapsed = now - snapshot.phaseStartedAt
		self.status.TextTransparency = 1 - math.clamp(math.min(elapsed, remaining) / S.Motion, 0, 1)
	elseif phase == "Result" then
		self.detail.Text = Copy.BackToQueue
	elseif phase == "Foul" then
		self.status.Text = Copy.Phase.Foul
		self.status.TextColor3 = color(S.Danger)
		local elapsed = now - snapshot.phaseStartedAt
		self.status.TextTransparency = 1 - math.clamp(math.min(elapsed, remaining) / S.Motion, 0, 1)
		self.detail.Text =
			string.format(Copy.FoulBy, nameFor(snapshot, snapshot.foul and snapshot.foul.by))
	elseif phase == "Waiting" or phase == "Countdown" then
		local count = 0
		for _, seat in snapshot.seats do
			if seat.connected ~= false then
				count += 1
			end
		end
		self.detail.Text = string.format(
			if self:soloAvailable() then Copy.SoloWaiting else Copy.Occupancy,
			count,
			snapshot.teamSize * 2
		)
	elseif phase == "Aiming" and isShooter then
		self.detail.Text = if snapshot.calledPocket
			then string.format(Copy.PocketChosen, snapshot.calledPocket)
			else Copy.YourTurn
	end
	self.clock.Text = if isClock
		then (if remaining <= 5 and phase == "Aiming"
			then string.format("%.1f", remaining)
			else tostring(math.ceil(remaining)))
		else ""
	if phase == "Waiting" and snapshot.cancelUntil and now < snapshot.cancelUntil then
		self.status.Text = Copy.CountdownCanceled
		self.status.TextColor3 = color(S.Danger)
	end
	self.clockScale.Scale = if phase == "Countdown"
		then 1 + S.CountdownScale * math.sin((remaining % 1) * math.pi)
		else 1
	self.clock.TextColor3 = color(if danger then S.Danger else S.Text)
	self.leave.Visible = phase ~= "Result"
	self.leave.Text = if phase == "Waiting" or phase == "Countdown"
		then Copy.LeaveQueue
		else Copy.Leave
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
				local elapsed = now - ball.changedAt
				ball.scale.Scale = if ball.down
						and elapsed >= 0
						and elapsed < S.Motion
					then 1 + 0.12 * math.sin(elapsed / S.Motion * math.pi)
					else 1
			end
		end
	end
	local offer = self:soloAvailable()
		and not self.modal.Visible
		and now - self.soloSentAt >= Config.Multiplayer.ActionRetrySeconds
	if not offer and GuiService.SelectedObject == self.soloButton then
		GuiService.SelectedObject = nil -- a hidden selection would keep play input off
	end
	self.soloOffer.Visible = offer
	local placementVisible = isShooter and self.placing and not self.precisionOpen
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
	self.setupLabel.TextColor3 = color(if self.placingBlocked then S.Danger else S.Text)
	local canPlay = isShooter and (phase == "Intro" or phase == "Placement" or phase == "Aiming")
	self.precisionButton.Visible = canPlay and not self.precisionOpen
	self.precision.Visible = canPlay and self.precisionOpen
	local foulLeft = self.foulUntil - now
	local showFoul = foulLeft > 0 and snapshot.phase ~= "Result" and not self:isModal()
	self.foulGroup.Visible = showFoul
	if showFoul then
		local margin, gap = S.HeaderMargin, S.HeaderGap
		local width = math.min(S.FoulCardWidth, self.root.AbsoluteSize.X - margin * 2)
		self.foulGroup.Size = UDim2.fromOffset(width, S.FoulCardHeight)
		self.foulGroup.Position = UDim2.new(0.5, 0, 0, (self.headerBottom or 0) + gap)
		local fade = 1 - math.clamp(foulLeft / S.FoulCardFadeSeconds, 0, 1)
		local base = self.foulPanelTransparency
		self.foulPanel.BackgroundTransparency = base + (1 - base) * fade
		self.foulStroke.Transparency = fade
		for _, stroke in self.foulPanel:GetChildren() do
			if stroke:IsA("UIStroke") and stroke ~= self.foulStroke then
				stroke.Transparency = fade
			end
		end
		self.foulTitle.TextTransparency = fade
		self.foulReason.TextTransparency = fade
		local inner = width - gap * 2
		self.foulTitle.Position = UDim2.fromOffset(gap, gap / 2)
		self.foulTitle.Size = UDim2.fromOffset(inner, S.StatusSize + gap / 2)
		self.foulReason.Position = UDim2.fromOffset(gap, S.StatusSize + gap)
		self.foulReason.Size = UDim2.fromOffset(inner, S.StatusSize * 2 + 4)
	end
	self.overlay.Visible = phase == "CoinFlip" or phase == "Result"
	if self.overlay.Visible then
		local duration = if phase == "CoinFlip"
			then Config.Multiplayer.CoinSeconds
			else Config.Multiplayer.ResultSeconds
		local elapsed = math.max(0, now - snapshot.phaseStartedAt)
		self.presentationScale.Scale = S.PanelEntranceScale
			+ (1 - S.PanelEntranceScale) * math.clamp(elapsed / S.Motion, 0, 1)
		self.overlay.GroupTransparency = 1
			- math.clamp(math.min(elapsed, duration - elapsed) / S.Motion, 0, 1)
		self.coin.Visible = phase == "CoinFlip"
		self.coinOwner.Visible = phase == "CoinFlip"
		if phase == "CoinFlip" and snapshot.coin then
			local coin = snapshot.coin
			local progressCoin = math.clamp(elapsed / (duration * 0.7), 0, 1)
			local turn = (1 - (1 - progressCoin) ^ 3) * math.pi * 8
			local landed = progressCoin >= 1
			local heads = if landed then coin.winnerTeam == coin.headsTeam else math.cos(turn) >= 0
			self.coin.Size = UDim2.fromOffset(
				S.ButtonHeight * 1.65 * math.max(0.08, math.abs(math.cos(turn))),
				S.ButtonHeight * 1.65
			)
			self.coin.Rotation = math.sin(turn / 2) * 12 * (1 - progressCoin)
			self.coinGlyph.Text = if heads then Copy.CoinHeadGlyph else Copy.CoinTailGlyph
			self.presentationTitle.Text = if landed
				then (if heads then Copy.Heads else Copy.Tails)
				else Copy.CoinTitle
			self.presentationTitle.TextColor3 = color(S.Gold)
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
			self.presentationTitle.Text = if not result or not result.winner
				then Copy.Draw
				elseif win then Copy.Win
				else Copy.Lose
			self.presentationTitle.TextColor3 = color(if win then S.Active else S.Danger)
			self.presentationText.Text = if result
					and snapshot.solo
					and result.reason == "Surrender"
				then Copy.SoloEnded
				elseif result then Copy.ResultReasons[result.reason] or Copy.BackToQueue
				else Copy.BackToQueue
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
end

return MatchHUD
