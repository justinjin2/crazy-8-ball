--!strict
-- ResultScreen: the end of a match, the same screen for every player in it (it replaces YOU WIN
-- and YOU LOSE; reference assets/ui/reference/05-match-result-vs.webp, in our light house style).
-- Built from the server's MatchSummary (Ranking); the client only animates its numbers.
--
-- - The face-off: your side on the left, theirs on the right, VS between. A white card per
--   player (team-mates side by side, smaller) with the avatar headshot, the name (never
--   translated; "..." when long) and the rank badge on the portrait's outer top corner. The
--   winner's side gets WINNER over it, gold rays turning behind it, and a crown that drops onto
--   each winner's portrait and rocks there, twinkling. A draw says DRAW and crowns nobody; a
--   player who left is faded with LEFT. Solo: one card, SOLO GAME, no VS.
-- - Your rewards, quickly, beside it (under it on a narrow screen): the XP bar of your division
--   fills with a rising tick (+250), drains in red (-150, Expert and up), or holds with a
--   "No XP lost" chip; crossing a division the bar flashes full, the badge pops into the next
--   and the bar carries on. Then the money counts up line by line (balls, nice shots, the match
--   bonus, a rank reward) to the Total, whose chip flies into the money HUD.
-- - About 5 to 6 s in all (Config.UI.Progress.Result). A tap or click anywhere, or gamepad A or
--   B, skips to the end; then Continue (or another tap, or A or B), or it closes by itself.
--   After it closes, NEW RANK! (or the rank-down card) follows when the match changed your
--   division.
--
-- Money: the pots' money already flew into the HUD during play, so only the match bonus and the
-- rank reward are new here. They are told to the HUD the moment the screen opens (expect) and
-- land with the total chip, so the HUD neither jumps early nor counts anything twice.
--
-- Laid out once at a natural size and scaled to the screen (a UIScale), like the match bar.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local ProgressionRules = Shared:WaitForChild("Progression")
local Format = require(ProgressionRules:WaitForChild("Format"))
local Ranks = require(ProgressionRules:WaitForChild("Ranks"))
local HudParts = require(script.Parent.HudParts)
local RankBadge = require(script.Parent.RankBadge)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local C = Config.UI.Progress.Result
local K = Config.UI.Kit
local P = Strings.Progress
local RankWords = Strings.Ranks
local ResultScreen = {}
ResultScreen.__index = ResultScreen

export type ResultScreen = {
	show: (self: ResultScreen, summary: any, onDone: (() -> ())?) -> (),
	isOpen: (self: ResultScreen) -> boolean,
	destroy: (self: ResultScreen) -> (),
}

local tone = HudParts.tone
local frame = HudParts.frame

-- The input binding that makes A and B skip or continue while the screen is up (above the
-- game's own gamepad binding, Input.luau, so they never reach the table).
local ACTION = "8ballResultScreen"

-- Headshots already fetched, by user id (shared by every result screen this session).
local headshots: { [number]: string } = {}

-- A whole, finite, non-negative amount (anything else counts as nothing).
local function clean(amount: any): number
	if type(amount) ~= "number" or amount ~= amount or amount == math.huge or amount <= 0 then
		return 0
	end
	return math.floor(amount)
end

-- Land money the HUD was told of but whose chip never flew (a screen closed or failed early).
local function payBack(money: any, amount: number)
	if amount > 0 then
		money:land(amount)
	end
end

local function isGamepad(): boolean
	return UserInputService:GetLastInputType() == Enum.UserInputType.Gamepad1
end

-- Put a player's headshot in `image` (cached; fetched once, in the background).
local function loadHeadshot(userId: number, image: ImageLabel, fallback: TextLabel)
	local cached = headshots[userId]
	if cached then
		image.Image = cached
		fallback.Visible = false
		return
	end
	if userId <= 0 then
		return
	end
	task.spawn(function()
		local ok, content, ready = pcall(function()
			return Players:GetUserThumbnailAsync(
				userId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size150x150
			)
		end)
		if ok and type(content) == "string" and ready then
			headshots[userId] = content
			if image.Parent then
				image.Image = content
				fallback.Visible = false
			end
		end
	end)
end

--------------------------------------------------------------------------------------------
-- The XP bar's plan and what it shows at a moment
--------------------------------------------------------------------------------------------

type Shown = { index: number, tier: string, division: number, into: number, width: number? }

local function fromRank(rank: any): Shown
	local r: any = if type(rank) == "table" then rank else {}
	local index = if type(r.index) == "number" then r.index else 0
	local tier = if type(r.tier) == "string" then r.tier else "Unranked"
	return {
		index = index,
		tier = tier,
		division = if type(r.division) == "number" then r.division else 0,
		into = if type(r.xpInDivision) == "number" then r.xpInDivision else 0,
		width = if type(r.width) == "number" then r.width else nil,
	}
end

-- The division shown at total XP `x`. Rising, a division's very top shows that division full
-- (not the next one empty), so the bar fills before the badge moves on.
local function shownAt(x: number, rising: boolean, xp: any): Shown
	local whole = math.floor(x + 0.5)
	if rising and whole <= xp.xpBefore and fromRank(xp.before).index == 0 then
		return fromRank(xp.before) -- Unranked until the first XP arrives
	end
	local rank = Ranks.fromXp(whole, true)
	local index, into, width = rank.index, rank.xpInDivision, rank.width
	if rising and into == 0 and index > 1 and whole > xp.xpBefore then
		index -= 1
		width = Ranks.width(index)
		into = width or 0
	end
	local tier, division = Ranks.at(index)
	return { index = index, tier = tier, division = division, into = into, width = width }
end

type Segment = { t0: number, t1: number, from: number, to: number, crosses: boolean }

-- The XP change split at every division it crosses, each part timed by its share of the whole
-- (at least XpMinSegmentSeconds), with a flash pause at each crossing. Returns the parts and
-- when the bar is done.
local function planXp(xp: any): ({ Segment }, number)
	local segments: { Segment } = {}
	local t = C.XpAt
	if type(xp) ~= "table" or type(xp.xpBefore) ~= "number" or type(xp.xpAfter) ~= "number" then
		return segments, t
	end
	local from, to = xp.xpBefore, xp.xpAfter
	local total = math.abs(to - from)
	if total == 0 then
		return segments, t
	end
	local rising = to > from
	local x = from
	for _ = 1, 64 do
		if x == to then
			break
		end
		local rank = Ranks.fromXp(x, true)
		local stop, crosses
		if rising then
			local nextStart = if rank.index < Ranks.count()
				then Ranks.startXp(rank.index + 1)
				else math.huge
			stop = math.min(to, nextStart)
			crosses = stop == nextStart
		else
			local start = Ranks.startXp(rank.index)
			if start >= x then -- at the bottom of a division: drain the one below
				start = Ranks.startXp(math.max(1, rank.index - 1))
			end
			stop = math.max(to, start)
			crosses = stop ~= to
		end
		if stop == x then
			break
		end
		local seconds =
			math.max(C.XpMinSegmentSeconds, C.XpFillSeconds * math.abs(stop - x) / total)
		table.insert(segments, { t0 = t, t1 = t + seconds, from = x, to = stop, crosses = crosses })
		t += seconds
		if crosses then
			t += C.XpFlashSeconds
		end
		x = stop
	end
	return segments, t
end

--------------------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------------------

--- The result screen, built into `screen` (UI.screen()). Its total chip flies with `flyer`
--- into `money`; `newRank` (optional) shows NEW RANK! or the rank-down card after it closes.
function ResultScreen.new(screen: ScreenGui, flyer: any, money: any, newRank: any?): ResultScreen
	local self: any = setmetatable({}, ResultScreen)
	self.alive = true
	self.flyer = flyer
	self.money = money
	self.newRank = newRank
	self.queue = {}
	self.view = nil
	self.root = frame(screen, "ResultScreen")
	self.root.Size = UDim2.fromScale(1, 1)
	self.root.ZIndex = C.ZIndex
	self.root.Visible = false
	self.sizeChanged = self.root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:layout()
	end)
	return self
end

-- One player's card: the headshot, the badge on the outer top corner, the name under it, a
-- crown for a winner, LEFT for a player who left.
local function makePlayer(parent: Instance, player: any, winner: boolean, zIndex: number): any
	local root = frame(parent, "Player")
	root.ZIndex = zIndex
	local card = HudParts.card(root, "Portrait", Config.Multiplayer.Style.PortraitCornerPx)
	local fallback = HudParts.text(card, "Fallback", K.Text.Heading, Strings.Match.AvatarFallback)
	fallback.Size = UDim2.fromScale(1, 1)
	local image = Instance.new("ImageLabel")
	image.Name = "Avatar"
	image.BackgroundTransparency = 1
	image.ScaleType = Enum.ScaleType.Fit
	image.Position = UDim2.fromOffset(3, 3)
	image.Size = UDim2.new(1, -6, 1, -6)
	image.ZIndex = 1
	image.Parent = card
	HudParts.corner(image, Config.Multiplayer.Style.PortraitCornerPx - 2)
	local userId = if type(player.userId) == "number" then player.userId else 0
	loadHeadshot(userId, image, fallback)
	local badge = RankBadge.new(card, { size = 32, interactive = false, name = "Rank", zIndex = 6 })
	badge.root.AnchorPoint = Vector2.new(0.5, 0.5)
	badge:set(
		if type(player.tier) == "string" then player.tier else "Unranked",
		if type(player.division) == "number" then player.division else 0
	)
	local rawName = if C.UseDisplayName then player.displayName or player.name else player.name
	local name = HudParts.text(root, "Name", C.NameTextPx, tostring(rawName or ""))
	name.AutoLocalize = false -- a player's name is never translated
	name.TextScaled = false
	name.TextWrapped = false
	name.TextTruncate = Enum.TextTruncate.AtEnd -- a long name ends in "..."
	local left = nil
	if player.left == true then
		image.ImageTransparency = C.LeftFade
		left = HudParts.pill(card, "LeftTag", tone("Red"))
		left.AnchorPoint = Vector2.new(0.5, 0.5)
		left.ZIndex = 7
		local words = HudParts.text(left, "Text", K.Text.Body, P.Left)
		words.Size = UDim2.fromScale(1, 1)
		words.TextWrapped = false
	end
	local crown, sparkles = nil, {}
	if winner then
		crown = HudParts.icon(card, "Crown", "Crown")
		crown.AnchorPoint = Vector2.new(0.5, 1)
		crown.ZIndex = 8
		crown.Visible = false
		for i, spot in { { 0.18, 0.3 }, { 0.84, 0.18 } } do
			local star = Instance.new("ImageLabel")
			star.Name = "Twinkle" .. i
			star.BackgroundTransparency = 1
			star.Image = Config.UI.Ranks.Sparkle
			star.AnchorPoint = Vector2.new(0.5, 0.5)
			star.Position = UDim2.fromScale(spot[1], spot[2])
			star.Size = UDim2.fromOffset(0, 0)
			star.ZIndex = 2
			star.Parent = crown
			table.insert(sparkles, star)
		end
	end
	return {
		root = root,
		card = card,
		fill = card:FindFirstChild("Fill"),
		image = image,
		badge = badge,
		name = name,
		left = left,
		crown = crown,
		sparkles = sparkles,
	}
end

-- One line of the money list: what it is on the left, the amount counting up on the right.
local function makeLine(parent: Instance, label: string, value: number): any
	local root = frame(parent, "Line")
	root.Visible = false
	local words = HudParts.note(root, "Label", C.LineTextPx, label)
	words.TextXAlignment = Enum.TextXAlignment.Left
	words.TextWrapped = false
	words.Size = UDim2.fromScale(0.68, 1)
	local amount = HudParts.text(root, "Amount", C.LineTextPx + 2, Format.money(0))
	amount.AutoLocalize = false -- only a number
	amount.TextWrapped = false
	amount.TextXAlignment = Enum.TextXAlignment.Right
	amount.AnchorPoint = Vector2.new(1, 0)
	amount.Position = UDim2.fromScale(1, 0)
	amount.Size = UDim2.fromScale(0.32, 1)
	return { root = root, amount = amount, value = value, t0 = 0, shown = false, last = 0 }
end

-- Build the whole screen for one summary.
function ResultScreen.build(self: any, view: any)
	local summary = view.summary
	local root = frame(self.root, "Match")
	root.Size = UDim2.fromScale(1, 1)
	view.root = root
	-- The dim over the game; a tap or click on it skips or continues.
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.BorderSizePixel = 0
	backdrop.BackgroundColor3 = tone("Ink")
	backdrop.BackgroundTransparency = 1
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.Selectable = false
	backdrop.Active = true
	backdrop.Modal = true -- frees a locked mouse
	backdrop.ZIndex = 0
	backdrop.Parent = root
	backdrop.Activated:Connect(function()
		self:tap()
	end)
	view.backdrop = backdrop
	-- The holder is the natural size, scaled to fit the screen; the stage inside it pops in and
	-- out (one UIScale each: an object takes only one).
	local holder = frame(root, "Holder")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.ZIndex = 1
	view.holder = holder
	view.fit = Instance.new("UIScale")
	view.fit.Name = "Fit"
	view.fit.Parent = holder
	local stage = frame(holder, "Stage")
	stage.AnchorPoint = Vector2.new(0.5, 0.5)
	stage.Position = UDim2.fromScale(0.5, 0.5)
	stage.Size = UDim2.fromScale(1, 1)
	stage.Visible = false
	view.stage = stage

	-- The face-off.
	local mine = if type(summary.you) == "table" and summary.you.team == 2 then 2 else 1
	local teams = if type(summary.teams) == "table" then summary.teams else {}
	local winner = summary.winner
	local solo = summary.solo == true
	local face = frame(stage, "FaceOff")
	view.face = face
	view.sides = {}
	local sideTeams: { number } = if solo then { mine } else { mine, 3 - mine }
	for i, team in sideTeams do
		local list = if type(teams[team]) == "table" then teams[team] else {}
		local won = not solo and winner == team
		local side = frame(face, if i == 1 then "YourSide" else "TheirSide")
		side.ZIndex = 1
		local rays = nil
		if won then
			rays = Instance.new("ImageLabel")
			rays.Name = "Rays"
			rays.BackgroundTransparency = 1
			rays.Image = K.Art.Rays
			rays.ImageColor3 = tone("Gold")
			rays.ImageTransparency = 1
			rays.AnchorPoint = Vector2.new(0.5, 0.5)
			rays.ZIndex = 0
			rays.Parent = side
		end
		local players = {}
		for _, player in list do
			if type(player) == "table" then
				table.insert(players, makePlayer(side, player, won, 1))
			end
		end
		table.insert(view.sides, {
			root = side,
			players = players,
			won = won,
			rays = rays,
			outer = if i == 1 then -1 else 1, -- the badge corner: left side left, right side right
		})
	end
	-- WINNER over the winner's side; DRAW or SOLO GAME over the whole face-off.
	local titleText = if solo then P.SoloGame elseif winner == nil then P.Draw else P.Winner
	view.title = HudParts.text(
		face,
		"Title",
		C.TitleTextPx,
		titleText,
		tone(if solo or winner == nil then "White" else "Gold")
	)
	view.title.TextWrapped = false
	view.title.ZIndex = 3
	view.title.Visible = false
	view.vs = nil
	if not solo then
		view.vs = HudParts.text(face, "Vs", C.VsTextPx, P.Vs, tone("Gold"))
		view.vs.TextWrapped = false
		view.vs.ZIndex = 3
	end

	-- The rewards card.
	local card = HudParts.card(stage, "Rewards")
	view.card = card
	local content = frame(card, "Content")
	view.content = content
	local xp = if not solo and type(summary.xp) == "table" then summary.xp else nil
	view.xp = xp
	view.xpBlock = nil
	view.note = nil
	if xp then
		local block = frame(content, "Xp")
		view.xpBlock = block
		view.xpBadge = RankBadge.new(block, {
			size = C.XpBadgePx,
			interactive = false,
			shine = true,
			name = "Rank",
			zIndex = 3,
		})
		view.rankName = HudParts.text(block, "RankName", C.XpNameTextPx, "")
		view.rankName.TextWrapped = false
		view.rankName.TextXAlignment = Enum.TextXAlignment.Left
		local delta = clean(math.abs(if type(xp.delta) == "number" then xp.delta else 0))
		local negative = type(xp.delta) == "number" and xp.delta < 0
		view.delta = HudParts.text(
			block,
			"Delta",
			C.XpNameTextPx - 2,
			P.XpDelta:format((if negative then "-" else "+") .. Format.xp(delta)),
			tone(if negative then "Red" else "Green")
		)
		view.delta.AutoLocalize = false
		view.delta.TextWrapped = false
		view.delta.TextXAlignment = Enum.TextXAlignment.Right
		view.delta.Visible = false
		if delta == 0 then
			view.noLoss = HudParts.pill(block, "NoXpLost", tone("Blue"))
			view.noLoss.Visible = false
			local words = HudParts.text(view.noLoss, "Text", K.Text.Min, P.NoXpLost)
			words.TextWrapped = false
			words.Position = UDim2.fromOffset(6, 0)
			words.Size = UDim2.new(1, -12, 1, 0)
			view.delta.Text = ""
		end
		view.bar = HudParts.pill(block, "Bar", tone("Soft"))
		view.barFill = frame(view.bar, "Fill")
		view.barFill.BackgroundTransparency = 0
		view.barFill.BackgroundColor3 = tone("Gold")
		view.barFill.ZIndex = 1
		HudParts.corner(view.barFill, K.PillCornerPx)
		view.barText = HudParts.text(view.bar, "XpText", C.XpTextPx, "")
		view.barText.AutoLocalize = false
		view.barText.TextWrapped = false
		view.barText.ZIndex = 2
	elseif solo or summary.short == true then
		view.note = HudParts.note(content, "Note", K.Text.Body, if solo then P.SoloNoXp else P.NoXp)
	end
	view.segments, view.xpEnd = planXp(xp)
	view.shown = nil -- the division the bar shows (Shown), once drawn

	-- The money list: balls, nice shots, the match bonus and a rank reward, then the Total.
	local m = if type(summary.money) == "table" then summary.money else {}
	local outcome = if type(summary.you) == "table" then summary.you.outcome else nil
	view.lines = {}
	local function add(label: string, value: number)
		table.insert(view.lines, makeLine(content, label, value))
	end
	add(P.BallsLine:format(clean(m.balls)), clean(m.ballMoney))
	if clean(m.nice) > 0 then
		add(P.NiceLine:format(clean(m.nice)), clean(m.niceMoney))
	end
	if clean(m.bonus) > 0 then
		add(if outcome == "Win" then P.WinBonus else P.LossBonus, clean(m.bonus))
	end
	if clean(m.reward) > 0 then
		add(P.RankReward, clean(m.reward))
	end
	view.total = clean(m.total)
	local total = HudParts.pill(content, "Total", tone("Gold"))
	total.Visible = false
	view.totalPill = total
	view.totalIcon = HudParts.icon(total, "CashStack", "Cash")
	view.totalIcon.ZIndex = 2
	view.totalLabel = HudParts.text(total, "Label", C.TotalTextPx, P.Total)
	view.totalLabel.TextWrapped = false
	view.totalLabel.TextXAlignment = Enum.TextXAlignment.Left
	view.totalAmount = HudParts.text(total, "Amount", C.TotalTextPx, Format.money(0))
	view.totalAmount.AutoLocalize = false
	view.totalAmount.TextWrapped = false
	view.totalAmount.TextXAlignment = Enum.TextXAlignment.Right
	view.continue = HudParts.candy(content, P.Continue, function()
		UISound.play("Click")
		self:close()
	end, "Green")
	view.continue.Name = "Continue"
	view.continue.Visible = false

	-- The timeline, seconds from opening.
	local t = C.MoneyAt
	for _, line in view.lines do
		line.t0 = t
		t += C.LineSeconds
	end
	view.totalAt = t
	view.chipAt = t + C.TotalSeconds + C.ChipDelaySeconds
	view.continueAt =
		math.max(view.chipAt + C.ContinueDelaySeconds, view.xpEnd + C.ContinueDelaySeconds)
end

--------------------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------------------

-- Lay out one side of the face-off in a box `width` wide, the portraits `size` square with
-- their top at `top`.
local function layoutSide(side: any, width: number, size: number, top: number)
	local count = #side.players
	local row = count * size + math.max(0, count - 1) * C.PortraitGap
	local left = (width - row) / 2
	local badgeSize = math.floor(size * C.BadgeShare)
	local crownSize = math.floor(size * C.CrownShare)
	local nameSize = if count > 1 then C.TeamNameTextPx else C.NameTextPx
	for n, p in side.players do
		local x = left + (n - 1) * (size + C.PortraitGap)
		p.root.Position = UDim2.fromOffset(x, top)
		p.root.Size = UDim2.fromOffset(size, size + C.NameHeight)
		p.card.Size = UDim2.fromOffset(size, size)
		p.badge:setSize(badgeSize)
		p.badge.root.Position = UDim2.fromOffset(if side.outer < 0 then 0 else size, 0)
		p.name.Position = UDim2.fromOffset(-C.PortraitGap / 2, size + 2)
		p.name.Size = UDim2.fromOffset(size + C.PortraitGap, C.NameHeight - 2)
		HudParts.setTextSize(p.name, nameSize, nameSize)
		if p.left then
			p.left.Position = UDim2.fromScale(0.5, 1)
			p.left.Size = UDim2.fromOffset(math.min(size, 70), math.max(20, math.floor(size * 0.2)))
		end
		if p.crown then
			p.crown.Size = UDim2.fromOffset(crownSize, crownSize)
			p.crownRest = math.floor(crownSize * C.CrownOverlap)
			p.crownSize = crownSize
		end
	end
	if side.rays then
		local raysSize = width * C.RaysShare
		side.rays.Position = UDim2.fromOffset(width / 2, top + size / 2)
		side.rays.Size = UDim2.fromOffset(raysSize, raysSize)
	end
end

function ResultScreen.layout(self: any)
	local view = self.view
	local screenSize = self.root.AbsoluteSize
	if not view or screenSize.X <= 0 or screenSize.Y <= 0 then
		return
	end
	local gap = C.ColumnGap
	local availableX = screenSize.X - C.MarginPx * 2
	local availableY = screenSize.Y - C.MarginPx * 2
	-- Side by side, or the rewards under the face-off: whichever lets it be bigger.
	local wideWidth = C.FaceWidth + gap + C.RewardsWidth
	local stackWidth = math.max(C.FaceWidth, C.RewardsWidth)
	local stackHeight = C.StackedFaceHeight + gap + C.Height
	local wideScale = math.min(availableX / wideWidth, availableY / C.Height)
	local stackScale = math.min(availableX / stackWidth, availableY / stackHeight)
	local stacked = stackScale > wideScale
	local faceHeight = if stacked then C.StackedFaceHeight else C.Height
	if stacked then
		view.holder.Size = UDim2.fromOffset(stackWidth, stackHeight)
		view.face.Position = UDim2.fromOffset((stackWidth - C.FaceWidth) / 2, 0)
		view.card.Position = UDim2.fromOffset((stackWidth - C.RewardsWidth) / 2, faceHeight + gap)
	else
		view.holder.Size = UDim2.fromOffset(wideWidth, C.Height)
		view.face.Position = UDim2.fromOffset(0, 0)
		view.card.Position = UDim2.fromOffset(C.FaceWidth + gap, 0)
	end
	view.fit.Scale = math.max(0.1, math.min(C.MaxScale, if stacked then stackScale else wideScale))
	view.face.Size = UDim2.fromOffset(C.FaceWidth, faceHeight)
	view.card.Size = UDim2.fromOffset(C.RewardsWidth, C.Height)

	-- The face-off: the title, the crowns' room, the portraits, the names; centred.
	local solo = #view.sides == 1
	local sideWidth = if solo then C.FaceWidth else (C.FaceWidth - C.VsWidth) / 2
	local most = 1
	for _, side in view.sides do
		most = math.max(most, #side.players)
	end
	local size = math.floor(
		math.min(
			C.PortraitPx,
			(sideWidth - (most - 1) * C.PortraitGap) / (most + C.BadgeShare * 0.5)
		)
	)
	local crownRoom = math.floor(size * C.CrownShare * (1 - C.CrownOverlap))
	local block = C.TitleHeight + crownRoom + size + C.NameHeight
	local top = math.max(0, (faceHeight - block) / 2)
	local portraitTop = top + C.TitleHeight + crownRoom
	for i, side in view.sides do
		local x = if solo then 0 elseif i == 1 then 0 else sideWidth + C.VsWidth
		side.root.Position = UDim2.fromOffset(x, 0)
		side.root.Size = UDim2.fromOffset(sideWidth, faceHeight)
		layoutSide(side, sideWidth, size, portraitTop)
	end
	-- WINNER over the winner's side, or DRAW / SOLO GAME over everything.
	local titleLeft, titleWidth = 0, C.FaceWidth
	for i, side in view.sides do
		if side.won then
			titleLeft = if i == 1 then 0 else sideWidth + C.VsWidth
			titleWidth = sideWidth
		end
	end
	view.title.Position = UDim2.fromOffset(titleLeft, top)
	view.title.Size = UDim2.fromOffset(titleWidth, C.TitleHeight)
	if view.vs then
		view.vs.AnchorPoint = Vector2.new(0.5, 0.5)
		view.vs.Position = UDim2.fromOffset(sideWidth + C.VsWidth / 2, portraitTop + size / 2)
		view.vs.Size = UDim2.fromOffset(C.VsWidth, C.VsTextPx + 8)
	end

	-- The rewards card, top to bottom: XP (or a note), the money lines, Total, Continue.
	local pad = C.PaddingPx
	local inner = C.RewardsWidth - pad * 2
	view.content.Position = UDim2.fromOffset(pad, pad)
	view.content.Size = UDim2.fromOffset(inner, C.Height - pad * 2)
	local y = 0
	if view.xpBlock then
		local badge = C.XpBadgePx
		local textLeft = badge + 8
		local deltaWidth = C.XpDeltaWidth
		view.xpBlock.Position = UDim2.fromOffset(0, 0)
		view.xpBlock.Size = UDim2.fromOffset(inner, C.XpHeight)
		view.xpBadge.root.Position = UDim2.fromOffset(0, (C.XpHeight - badge) / 2)
		view.xpBadge:setSize(badge)
		local rowHeight = C.XpNameTextPx + 6
		view.rankName.Position = UDim2.fromOffset(textLeft, 2)
		view.rankName.Size = UDim2.fromOffset(inner - textLeft - deltaWidth, rowHeight)
		view.delta.AnchorPoint = Vector2.new(1, 0)
		view.delta.Position = UDim2.fromOffset(inner, 2)
		view.delta.Size = UDim2.fromOffset(deltaWidth, rowHeight)
		if view.noLoss then
			view.noLoss.AnchorPoint = Vector2.new(1, 0)
			view.noLoss.Position = UDim2.fromOffset(inner, 4)
			view.noLoss.Size = UDim2.fromOffset(deltaWidth + 8, rowHeight - 4)
		end
		view.bar.Position = UDim2.fromOffset(textLeft, rowHeight + 8)
		view.bar.Size = UDim2.fromOffset(inner - textLeft, C.XpBarHeight)
		view.barText.Size = UDim2.fromScale(1, 1)
		y = C.XpHeight + 10
	elseif view.note then
		view.note.Position = UDim2.fromOffset(0, 0)
		view.note.Size = UDim2.fromOffset(inner, K.Text.Body + 10)
		y = K.Text.Body + 18
	end
	for _, line in view.lines do
		line.root.Position = UDim2.fromOffset(0, y)
		line.root.Size = UDim2.fromOffset(inner, C.LineHeight)
		y += C.LineHeight + C.LineGap
	end
	y += 4
	local totalHeight = C.TotalHeight
	view.totalPill.Position = UDim2.fromOffset(0, y)
	view.totalPill.Size = UDim2.fromOffset(inner, totalHeight)
	view.totalIcon.Position = UDim2.fromOffset(6, 2)
	view.totalIcon.Size = UDim2.fromOffset(totalHeight * 1.3, totalHeight - 4)
	local labelLeft = math.floor(totalHeight * 1.3) + 10
	view.totalLabel.Position = UDim2.fromOffset(labelLeft, 1)
	view.totalLabel.Size = UDim2.fromOffset(inner / 2 - labelLeft, totalHeight - 2)
	view.totalAmount.Position = UDim2.fromOffset(inner / 2, 1)
	view.totalAmount.Size = UDim2.fromOffset(inner / 2 - 10, totalHeight - 2)
	local buttonHeight = C.ButtonHeight
	view.continue.Position = UDim2.fromOffset(0, C.Height - pad * 2 - buttonHeight)
	view.continue.Size = UDim2.fromOffset(inner, buttonHeight)
end

--------------------------------------------------------------------------------------------
-- Showing, step by step
--------------------------------------------------------------------------------------------

-- The money a summary adds that has not flown in yet: the match bonus and the rank reward.
local function newMoneyOf(summary: any): number
	local m = if type(summary.money) == "table" then summary.money else {}
	return clean(m.bonus) + clean(m.reward)
end

--- Show the end of a match: `summary` is the server's MatchSummary (Ranking; the /result
--- command's preview looks the same). `onDone` runs once the screen has closed (NEW RANK!, if
--- any, is then on its way). A summary that arrives while one is open waits its turn.
function ResultScreen.show(self: any, summary: any, onDone: (() -> ())?)
	if not self.alive or type(summary) ~= "table" then
		if onDone then
			task.spawn(onDone)
		end
		return
	end
	-- Only the match bonus and the rank reward are new money here (the pots already flew in
	-- during play): the HUD waits for them from now and they land with the total chip.
	self.money:expect(newMoneyOf(summary))
	if self.view then
		table.insert(self.queue, { summary = summary, onDone = onDone })
		return
	end
	self:open(summary, onDone)
end

function ResultScreen.open(self: any, summary: any, onDone: (() -> ())?)
	local view: any = {
		summary = summary,
		onDone = onDone,
		started = os.clock(),
		offset = 0, -- a skip moves the clock on
		skippedAt = -math.huge,
		closing = false,
		newMoney = newMoneyOf(summary), -- expected by the HUD since show()
		owed = true,
		chipSent = false,
		continueShown = false,
		crownLanded = false,
		lastXpTick = 0,
		lastMoneyTick = 0,
		flashed = {},
	}
	self.view = view
	local built, problem = pcall(function()
		self:build(view)
		self:layout()
	end)
	if not built then
		-- Never left half-open (it would hold back NEW RANK! for good): skip this one.
		warn("[8ball] ResultScreen: " .. tostring(problem))
		ContextActionService:UnbindAction(ACTION)
		view.closing = true
		if view.owed then
			view.owed = false
			payBack(self.money, view.newMoney)
		end
		self:finish(view)
		return
	end
	self.root.Visible = true
	TweenService:Create(
		view.backdrop,
		TweenInfo.new(K.Motion.PopSeconds, Enum.EasingStyle.Quad),
		{ BackgroundTransparency = C.BackdropTransparency }
	):Play()
	UIAnim.popIn(view.stage)
	ContextActionService:BindActionAtPriority(
		ACTION,
		function(_name: string, state: Enum.UserInputState, _input: InputObject)
			if state == Enum.UserInputState.Begin then
				self:tap()
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.ContextActionPriority.High.Value + 10,
		Enum.KeyCode.ButtonA,
		Enum.KeyCode.ButtonB
	)
	view.loop = RunService.RenderStepped:Connect(function()
		local ok, err = pcall(self.step, self, false)
		if not ok then
			warn("[8ball] ResultScreen: " .. tostring(err))
			self:close()
		end
	end)
end

-- The screen's clock: seconds since it opened, plus any skip.
local function clock(view: any): number
	return os.clock() - view.started + view.offset
end

--- A tap, click, A or B: skip to the end, or once there, continue.
function ResultScreen.tap(self: any)
	local view = self.view
	if not view or view.closing then
		return
	end
	local t = clock(view)
	if t < view.continueAt then
		view.offset += view.continueAt - t
		view.skippedAt = os.clock()
		self:step(true)
	elseif os.clock() - view.skippedAt >= C.SkipGuardSeconds then
		self:close()
	end
end

-- The face-off at time t: the title, the crowns dropping and rocking, the rays turning.
local function stepFace(view: any, t: number)
	if not view.title.Visible and t >= C.CrownAt * 0.5 then
		UIAnim.popIn(view.title)
	end
	local drop = (t - C.CrownAt) / C.CrownDropSeconds
	for _, side in view.sides do
		if side.rays then
			local shown = math.clamp((t - C.CrownAt) / K.Motion.PopSeconds, 0, 1)
			side.rays.ImageTransparency = 1 - (1 - C.RaysTransparency) * shown
			side.rays.Rotation = (t * K.Motion.RaysDegreesPerSecond) % 360
		end
		for _, p in side.players do
			local crown = p.crown
			if crown and p.crownSize then
				crown.Visible = drop > 0
				if drop > 0 then
					-- Down from above with a small overshoot, then a gentle rock.
					local fall = (1 - UIAnim.backOut(math.min(1, drop)))
						* p.crownSize
						* C.CrownDropShare
					crown.Position = UDim2.new(0.5, 0, 0, p.crownRest - fall)
					crown.ImageTransparency = 1 - math.clamp(drop * 3, 0, 1)
					local after = math.max(0, t - C.CrownAt - C.CrownDropSeconds)
					crown.Rotation = math.sin(after * 3) * C.CrownWobbleDegrees
					for i, star in p.sparkles do
						local twinkle = math.max(0, math.sin(after * 4 + i * 2.1))
						local px = p.crownSize * 0.34 * twinkle
						star.Size = UDim2.fromOffset(px, px)
					end
				end
			end
		end
	end
	if not view.crownLanded and drop >= 1 then
		view.crownLanded = true
		for _, side in view.sides do
			for _, p in side.players do
				if p.crown then
					UIAnim.bounce(p.crown)
					if p.fill then
						UIAnim.shine(p.fill)
					end
				end
			end
		end
	end
end

-- Draw the bar for one division.
local function drawBar(view: any, shown: Shown, pop: boolean): number
	local old: Shown? = view.shown
	if not old or old.index ~= shown.index then
		view.xpBadge:set(shown.tier, shown.division, pop and old ~= nil)
		view.rankName.Text = Ranks.name({
			tier = shown.tier,
			division = shown.division,
			index = shown.index,
			xpInDivision = shown.into,
			width = shown.width,
		})
	end
	view.shown = shown
	local fill
	if shown.index == 0 then
		fill = 0
		view.barText.Text = RankWords.XpOf:format(Format.xp(0), Format.xp(Ranks.width(1) or 0))
	elseif shown.width then
		fill = math.clamp(shown.into / shown.width, 0, 1)
		view.barText.Text = RankWords.XpOf:format(Format.xp(shown.into), Format.xp(shown.width))
	else
		fill = 1 -- the top tier has no top: just its XP
		view.barText.Text = RankWords.XpOnly:format(Format.xp(shown.into))
	end
	view.barFill.Visible = fill > 0.01
	view.barFill.Size = UDim2.fromScale(fill, 1)
	return fill
end

-- The XP bar at time t (quiet: a skip, so no ticks or chimes).
local function stepXp(view: any, t: number, quiet: boolean)
	local xp = view.xp
	if not xp then
		return
	end
	local segments: { Segment } = view.segments
	local rising = xp.xpAfter > xp.xpBefore
	if t >= C.XpAt then
		if not view.delta.Visible and view.delta.Text ~= "" then
			UIAnim.popIn(view.delta)
		end
		if view.noLoss and not view.noLoss.Visible then
			UIAnim.popIn(view.noLoss)
		end
	end
	-- Before the bar starts: the rank before; once it is done: the rank after (the server's);
	-- between: the part of the change running now, or the pause after it.
	local shown: Shown
	local moving, flashing = false, false
	if t < C.XpAt then
		shown = fromRank(xp.before)
	elseif t >= view.xpEnd then
		shown = fromRank(xp.after)
	else
		shown = fromRank(xp.before)
		for i, s in segments do
			if t < s.t1 then
				local k = math.clamp((t - s.t0) / (s.t1 - s.t0), 0, 1)
				shown = shownAt(s.from + (s.to - s.from) * k, rising, xp)
				moving = true
				break
			end
			local nextStart = if segments[i + 1] then segments[i + 1].t0 else view.xpEnd
			if t < nextStart then
				shown = shownAt(s.to, rising, xp)
				flashing = rising and s.crosses
				if flashing and not view.flashed[i] then
					view.flashed[i] = true
					if not quiet then
						UISound.play("XpFull")
					end
				end
				break
			end
		end
	end
	local fill = drawBar(view, shown, true)
	local draining = moving and not rising
	view.barFill.BackgroundColor3 = if flashing and math.floor(t * 12) % 2 == 0
		then tone("White")
		elseif draining then tone("Red")
		else tone("Gold")
	if moving and not quiet and os.clock() - view.lastXpTick >= C.XpTickEvery then
		view.lastXpTick = os.clock()
		local pitch = Config.Audio.XpTickPitch
		UISound.play(
			"XpTick",
			pitch.From + (pitch.To - pitch.From) * fill,
			if rising then 1 else 0.6
		)
	end
end

-- The money list at time t: each line pops and counts up in turn, then the Total, then the
-- total chip flies into the money HUD.
function ResultScreen.stepMoney(self: any, view: any, t: number, quiet: boolean)
	local ticked = false
	local count = C.LineSeconds * 0.85
	for _, line in view.lines do
		if t >= line.t0 then
			if not line.shown then
				line.shown = true
				UIAnim.popIn(line.root)
			end
			local value = math.floor(line.value * UIAnim.quadOut((t - line.t0) / count) + 0.5)
			if value ~= line.last then
				ticked = ticked or value > line.last
				line.last = value
				line.amount.Text = Format.money(value)
			end
		end
	end
	if t >= view.totalAt then
		if not view.totalPill.Visible then
			UIAnim.popIn(view.totalPill)
		end
		local k = UIAnim.quadOut((t - view.totalAt) / (C.TotalSeconds * 0.85))
		local value = math.floor(view.total * k + 0.5)
		local words = Format.money(value)
		if view.totalAmount.Text ~= words then
			ticked = true
			view.totalAmount.Text = words
		end
	end
	if ticked and not quiet and os.clock() - view.lastMoneyTick >= Config.Audio.MoneyTickEvery then
		view.lastMoneyTick = os.clock()
		UISound.play("MoneyTick")
	end
	if t >= view.chipAt and not view.chipSent then
		view.chipSent = true
		self:sendChip(view)
	end
end

-- The total chip: it shows the match's whole take but adds only the new money (the pots are
-- already in the HUD); with nothing at all it is skipped.
function ResultScreen.sendChip(self: any, view: any)
	if not view.owed then
		return
	end
	view.owed = false
	if view.total <= 0 and view.newMoney <= 0 then
		return -- nothing was earned: no chip, and the HUD was told of nothing
	end
	local pill = view.totalPill
	local from = pill.AbsolutePosition + pill.AbsoluteSize / 2
	self.flyer:fly(view.newMoney, from, "Total", 0, Format.moneyDelta(view.total))
	UIAnim.bounce(pill)
end

function ResultScreen.step(self: any, quiet: boolean)
	local view = self.view
	if not view or view.closing then
		return
	end
	local t = clock(view)
	stepFace(view, t)
	stepXp(view, t, quiet)
	self:stepMoney(view, t, quiet)
	if t >= view.continueAt and not view.continueShown then
		view.continueShown = true
		UIAnim.popIn(view.continue)
		if isGamepad() then
			GuiService.SelectedObject = view.continue
		end
	end
	if t >= view.continueAt + C.AutoCloseSeconds then
		self:close()
	end
end

--------------------------------------------------------------------------------------------
-- Closing
--------------------------------------------------------------------------------------------

function ResultScreen.close(self: any)
	local view = self.view
	if not view or view.closing then
		return
	end
	view.closing = true
	ContextActionService:UnbindAction(ACTION)
	-- Money the HUD is still waiting for lands now (the chip did not get to fly).
	if view.owed then
		view.owed = false
		payBack(self.money, view.newMoney)
	end
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(view.root) then
		GuiService.SelectedObject = nil
	end
	TweenService:Create(
		view.backdrop,
		TweenInfo.new(K.Motion.OutSeconds, Enum.EasingStyle.Quad),
		{ BackgroundTransparency = 1 }
	):Play()
	UIAnim.popOut(view.stage)
	task.delay(K.Motion.OutSeconds + 0.05, function()
		self:finish(view)
	end)
end

-- Take the closed screen down, then NEW RANK! (if the match moved your division), then the
-- caller's onDone, then the next summary waiting.
function ResultScreen.finish(self: any, view: any)
	if view.finished then
		return
	end
	view.finished = true
	if view.loop then
		view.loop:Disconnect()
	end
	for _, side in view.sides or {} do
		for _, p in side.players do
			p.badge:destroy()
		end
	end
	if view.xpBadge then
		view.xpBadge:destroy()
	end
	if view.root then
		view.root:Destroy()
	end
	if self.view == view then
		self.view = nil
	end
	self.root.Visible = false
	if not self.alive then
		return
	end
	local xp = view.xp
	if self.newRank and xp and (xp.promoted == true or xp.demoted == true) then
		self.newRank:show({
			kind = if xp.promoted then "Up" else "Down",
			before = xp.before,
			after = xp.after,
			reward = clean(xp.rewardTotal),
			newTier = xp.newTier == true,
			preview = view.summary.preview == true,
			paid = true, -- its reward already came in with this screen's total chip
		})
	end
	if view.onDone then
		task.spawn(view.onDone)
	end
	local nextOne = table.remove(self.queue, 1)
	if nextOne then
		self:open(nextOne.summary, nextOne.onDone)
	end
end

--- Whether the screen is up (or waiting to show).
function ResultScreen.isOpen(self: any): boolean
	return self.view ~= nil or #self.queue > 0
end

function ResultScreen.destroy(self: any)
	if not self.alive then
		return
	end
	self.alive = false
	-- Money still owed to the HUD lands at once, so it is not left waiting for it.
	for _, waiting in self.queue do
		payBack(self.money, newMoneyOf(waiting.summary))
	end
	self.queue = {}
	local view = self.view
	if view then
		self:close()
		self:finish(view)
	end
	self.sizeChanged:Disconnect()
	self.root:Destroy()
end

return ResultScreen
