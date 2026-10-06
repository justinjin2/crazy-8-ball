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
--   fills with a rising tick ("+250 XP"; XP is never lost, so a loss shows its small gain or
--   "+0 XP"), with a chip for each boost that was on under it ("ROOKIE x2", "FIRST WIN x2",
--   "STREAK +25%", "VIP +50%", from xp.breakdown.boosts); crossing a division the bar flashes
--   full, the badge pops into the next and the bar carries on. Then the money counts up line
--   by line (balls, nice shots, the match bonus, the win streak, a rank reward) to the Total,
--   whose chip flies into the money HUD. A winner's lucky block (summary.block, ECONOMY 7)
--   shows as a chip ("+1 Mystery Lucky Block" with its 3D icon; RewardChips) whose block flies
--   into the hotbar (or the left column's Inventory tile while the bar is hidden). The card
--   grows when all that needs more room; the whole screen scales to fit.
-- - About 5 to 6 s in all (Config.UI.Progress.Result). A tap or click anywhere, or gamepad A or
--   B, skips to the end; then Continue (or another tap, or A or B), or it closes by itself.
--   After it closes, NEW RANK! follows when the match took you to a new division, with the
--   rank rewards (xp.rewards: money, lucky blocks, the tier's cue) as its chips.
-- - After a two-sided game (designer, 2026-09-28) the PostMatch row takes Continue's place,
--   under both columns: Rematch, and Play another and Lobby in an arena (Leave on a lobby
--   table), with the series score in place of VS. Then the screen stays until the choice is
--   made (Main calls endChoices); NEW RANK! comes over it as the row appears.
--
-- Money: the pots' money already flew into the HUD during play, so only the match bonus, the
-- streak bonus and the rank reward are new here. They are told to the HUD the moment the screen
-- opens (expect) and land with the total chip, so the HUD neither jumps early nor counts
-- anything twice.
--
-- Laid out once at a natural size and scaled to the screen (a UIScale), like the match bar.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local ProgressionRules = Shared:WaitForChild("Progression")
local Format = require(ProgressionRules:WaitForChild("Format"))
local Ranks = require(ProgressionRules:WaitForChild("Ranks"))
local HudParts = require(script.Parent.HudParts)
local PostMatch = require(script.Parent.PostMatch)
local RankBadge = require(script.Parent.RankBadge)
local RewardChips = require(script.Parent.RewardChips)
local ScreenBlur = require(script.Parent.ScreenBlur)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local C = Config.UI.Progress.Result
local K = Config.UI.Kit
local P = Strings.Progress
local RankWords = Strings.Ranks
local BLOCK_NAMES: { [string]: string } = Strings.LuckyBlocks.Names :: any
local BOOST_TONES: { [string]: string } = C.BoostTones :: any
local RAINBOW: { { number } } = Config.UI.Progress.RankHud.ReyesColors :: any -- the house rainbow
local FONT: Enum.Font = (Enum.Font :: any)[K.Font]
local ResultScreen = {}
ResultScreen.__index = ResultScreen

export type ResultScreen = {
	show: (self: ResultScreen, summary: any, onDone: (() -> ())?) -> (),
	setDeps: (self: ResultScreen, deps: any) -> (),
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

-- The XP gain split at every division it crosses, each part timed by its share of the whole
-- (at least XpMinSegmentSeconds), with a flash pause at each crossing. Returns the parts and
-- when the bar is done. XP is never lost: a summary that went down (it cannot) just holds.
local function planXp(xp: any): ({ Segment }, number)
	local segments: { Segment } = {}
	local t = C.XpAt
	if type(xp) ~= "table" or type(xp.xpBefore) ~= "number" or type(xp.xpAfter) ~= "number" then
		return segments, t
	end
	local from, to = xp.xpBefore, xp.xpAfter
	local total = to - from
	if total <= 0 then
		return segments, t
	end
	local x = from
	for _ = 1, 64 do
		if x == to then
			break
		end
		local rank = Ranks.fromXp(x, true)
		local nextStart = if rank.index < Ranks.count()
			then Ranks.startXp(rank.index + 1)
			else math.huge
		local stop = math.min(to, nextStart)
		local crosses = stop == nextStart
		if stop == x then
			break
		end
		local seconds = math.max(C.XpMinSegmentSeconds, C.XpFillSeconds * (stop - x) / total)
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
--- into `money`; `newRank` (optional) shows NEW RANK! after it closes. The win's block needs
--- the economy's shared table (setDeps).
function ResultScreen.new(screen: ScreenGui, flyer: any, money: any, newRank: any?): ResultScreen
	local self: any = setmetatable({}, ResultScreen)
	self.alive = true
	self.screen = screen
	self.flyer = flyer
	self.money = money
	self.newRank = newRank
	self.deps = nil
	self.queue = {}
	self.view = nil
	self.onChoice = nil
	self.root = frame(screen, "ResultScreen")
	self.root.Size = UDim2.fromScale(1, 1)
	self.root.ZIndex = C.ZIndex
	self.root.Visible = false
	self.sizeChanged = self.root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:layout()
	end)
	return self
end

--- The economy's shared table (Progression): its `hotbarCenter` or `column` catches the win's
--- block.
function ResultScreen.setDeps(self: any, deps: any)
	self.deps = deps
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
	-- A bot's card (the Bots lane): its avatar's account, or the PC robot's picture.
	if player.bot == "Pc" then
		image.Image = Config.Bots.Robot.Icon
		fallback.Visible = false
	else
		loadHeadshot(
			if type(player.avatarUserId) == "number" then player.avatarUserId else userId,
			image,
			fallback
		)
	end
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

-- One XP boost's chip: "ROOKIE x2" in white kit text on its colour (VIP on the house rainbow),
-- sized to its words. Nil for a boost with no words.
local function makeBoost(parent: Instance, boost: any): any?
	if type(boost) ~= "table" or type(boost.kind) ~= "string" then
		return nil
	end
	local words = RewardChips.boostWords(boost.kind, boost.share)
	if not words then
		return nil
	end
	local toneName = BOOST_TONES[boost.kind] or "Blue"
	local rainbow = toneName == "Rainbow"
	local root = HudParts.pill(parent, "Boost", if rainbow then tone("White") else tone(toneName))
	root.Visible = false
	if rainbow then
		local keys = {}
		for i, c in RAINBOW do
			local at = if #RAINBOW > 1 then (i - 1) / (#RAINBOW - 1) else 0
			table.insert(keys, ColorSequenceKeypoint.new(at, HudParts.color(c)))
		end
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new(keys)
		gradient.Parent = root
	end
	local text = HudParts.text(root, "Words", C.BoostTextPx, words)
	text.TextWrapped = false
	text.Size = UDim2.fromScale(1, 1)
	text.ZIndex = 2
	return { root = root, words = words }
end

-- The size, in the screen's natural pixels, that kit text `px` tall is drawn at while the
-- screen is scaled by `shown` (at most 1). A kit text's UITextSizeConstraint keeps its
-- minimum on screen even inside a UIScale (TextScaled or not; STUDIO_NOTES), so on a small
-- screen small words take more of the natural layout than their size says.
local function drawnPx(px: number, shown: number): number
	if shown >= 1 then
		return px
	end
	return math.max(px, math.min(px, K.Text.Min) / shown)
end

-- How wide text `words` is, drawn `px` tall at scale `shown` (natural pixels).
local function drawnWidth(words: string, px: number, shown: number): number
	return TextService:GetTextSize(words, drawnPx(px, shown), FONT, Vector2.new(4000, 200)).X
end

-- Lay the boost chips out left to right from (x, y) in rows no wider than `width`, each as
-- wide as its words drawn at scale `shown`. Returns how tall they are.
local function flowBoosts(
	boosts: { any },
	x: number,
	y: number,
	width: number,
	shown: number
): number
	local left, top, rows = x, y, if #boosts > 0 then 1 else 0
	for _, boost in boosts do
		local wide = math.ceil(drawnWidth(boost.words, C.BoostTextPx, shown) + C.BoostPadPx * 2)
		local w = math.min(wide, width)
		if left > x and left + w > x + width then
			left = x
			top += C.BoostHeight + C.BoostGap
			rows += 1
		end
		boost.root.Position = UDim2.fromOffset(left, top)
		boost.root.Size = UDim2.fromOffset(w, C.BoostHeight)
		left += w + C.BoostGap
	end
	return if rows > 0 then rows * C.BoostHeight + (rows - 1) * C.BoostGap else 0
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
		-- A series (designer, 2026-09-28): its score, your side first, where VS stands.
		local series = summary.series
		local wins = type(series) == "table" and type(series.wins) == "table" and series.wins
		local vsText = if wins
			then Strings.PostMatch.SeriesScore:format(clean(wins[mine]), clean(wins[3 - mine]))
			else P.Vs
		view.vs = HudParts.text(face, "Vs", C.VsTextPx, vsText, tone("Gold"))
		view.vs.TextWrapped = false
		view.vs.AutoLocalize = wins == false
		view.vs.ZIndex = 3
	end
	-- A No ults queue match (the server's summary.noUlts): a small grey NO ULTS pill under VS.
	view.noUlts = nil
	if not solo and summary.noUlts == true then
		local U = Config.UI.Ults
		local pill = HudParts.pill(face, "NoUlts", HudParts.color(U.NoUltsColor))
		pill.AnchorPoint = Vector2.new(0.5, 0)
		pill.ZIndex = 3
		local words = HudParts.text(pill, "Words", U.NoUltsTextPx, Strings.Ults.Hud.NoUlts)
		words.TextWrapped = false
		words.Size = UDim2.new(1, -U.NoUltsPadPx, 1, -2)
		words.Position = UDim2.fromOffset(U.NoUltsPadPx / 2, 1)
		words.ZIndex = 4
		view.noUlts = pill
	end
	-- The choices after a two-sided game, in Continue's place.
	view.choices = nil
	if not solo and (summary.rematch == true or summary.arena == true) then
		view.choices = PostMatch.new(stage, function(kind: string)
			if self.onChoice and self.view == view and not view.closing then
				self.onChoice(kind, summary)
			end
		end)
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
	view.boosts = {}
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
		-- XP is never lost: the gain, or "+0 XP" (never a minus).
		local delta = clean(xp.delta)
		view.delta = HudParts.text(
			block,
			"Delta",
			C.XpNameTextPx - 2,
			P.XpDelta:format(Format.xp(delta)),
			tone(if delta > 0 then "Green" else "White")
		)
		view.delta.AutoLocalize = false
		view.delta.TextWrapped = false
		view.delta.TextXAlignment = Enum.TextXAlignment.Right
		view.delta.Visible = false
		-- A chip for each boost that was on (only with a gain: a boost on nothing is nothing).
		local breakdown = if type(xp.breakdown) == "table" then xp.breakdown else {}
		if delta > 0 and type(breakdown.boosts) == "table" then
			for _, boost in breakdown.boosts do
				local chip = makeBoost(content, boost)
				if chip then
					table.insert(view.boosts, chip)
				end
			end
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

	-- The money list: balls, nice shots, the match bonus, the win streak and a rank reward,
	-- then the Total.
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
	if clean(m.streak) > 0 then
		add(P.StreakLine, clean(m.streak))
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
	-- The winner's lucky block (block = { kind, readyAt }: already in the hotbar): its chip
	-- under the Total.
	view.blockChip = nil
	local block = summary.block
	local blockKind = if type(block) == "table" and type(block.kind) == "string"
		then block.kind
		else nil
	if blockKind and blockKind ~= "" then
		local chip = RewardChips.new(content, {
			kind = "Block",
			id = blockKind,
			text = P.WinBlock:format(1, BLOCK_NAMES[blockKind] or blockKind),
		}, C.BlockChipHeight, C.BlockChipTextPx)
		chip.words.AutoLocalize = true -- a block's name from Strings, not a player's
		view.blockChip = chip
	end
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
	view.blockAt = view.chipAt + C.BlockAfterSeconds -- the block chip
	view.blockFlyAt = view.blockAt + C.BlockFlySeconds
	view.continueAt = math.max(
		view.chipAt + C.ContinueDelaySeconds,
		view.xpEnd + C.ContinueDelaySeconds,
		if view.blockChip then view.blockAt + C.ContinueDelaySeconds else 0
	)
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

-- The rewards card's contents, top to bottom: the XP (or a note) and its boosts, the money
-- lines, Total, the win's block, and Continue at the bottom. Returns the card's
-- height: C.Height, or more when its contents need it.
function ResultScreen.layoutCard(_self: any, view: any): number
	local pad = C.PaddingPx
	local inner = C.RewardsWidth - pad * 2
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
		view.bar.Position = UDim2.fromOffset(textLeft, rowHeight + 8)
		view.bar.Size = UDim2.fromOffset(inner - textLeft, C.XpBarHeight)
		view.barText.Size = UDim2.fromScale(1, 1)
		y = C.XpHeight
		if #view.boosts > 0 then
			-- Under the bar, from its left end.
			y += C.BlockGap
			y += flowBoosts(view.boosts, textLeft, y, inner - textLeft, view.textScale or 1)
		end
		y += 10
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
	y += totalHeight
	local chip = view.blockChip
	if chip then
		-- Centred under the Total (never wider than the card: its words shrink).
		y += C.BlockGap
		local width = math.min(
			RewardChips.width(
				chip.spec,
				C.BlockChipHeight,
				drawnPx(C.BlockChipTextPx, view.textScale or 1)
			),
			inner
		)
		chip.root.Position = UDim2.fromOffset(math.floor((inner - width) / 2), y)
		chip.root.Size = UDim2.fromOffset(width, C.BlockChipHeight)
		y += C.BlockChipHeight
	end
	local buttonHeight = C.ButtonHeight
	if not view.choices then
		y += C.BlockGap + 2 + buttonHeight
	end
	local height = math.max(C.Height, y + pad * 2)
	view.content.Position = UDim2.fromOffset(pad, pad)
	view.content.Size = UDim2.fromOffset(inner, height - pad * 2)
	view.continue.Position = UDim2.fromOffset(0, height - pad * 2 - buttonHeight)
	view.continue.Size = UDim2.fromOffset(inner, buttonHeight)
	return height
end

function ResultScreen.layout(self: any, settled: boolean?)
	local view = self.view
	local screenSize = self.root.AbsoluteSize
	if not view or screenSize.X <= 0 or screenSize.Y <= 0 then
		return
	end
	local cardHeight = self:layoutCard(view)
	local gap = C.ColumnGap
	local availableX = screenSize.X - C.MarginPx * 2
	-- Lifted (the 1v1 result cutscene, GUI lane): the top part only, so both bodies show below.
	local lifted = self.lifted == true
	local availableY = (
		if lifted then screenSize.Y * Config.Cutscenes.Result.ScreenShare else screenSize.Y
	) - C.MarginPx * 2
	view.holder.AnchorPoint = Vector2.new(0.5, if lifted then 0 else 0.5)
	view.holder.Position = if lifted
		then UDim2.new(0.5, 0, 0, C.MarginPx)
		else UDim2.fromScale(0.5, 0.5)
	-- Side by side, or the rewards under the face-off: whichever lets it be bigger.
	local wideWidth = C.FaceWidth + gap + C.RewardsWidth
	local stackWidth = math.max(C.FaceWidth, C.RewardsWidth)
	local stackHeight = C.StackedFaceHeight + gap + cardHeight
	-- The choices row, when there is one, goes under everything.
	local extra = if view.choices then C.ChoicesGap + PostMatch.height() else 0
	local wideScale = math.min(availableX / wideWidth, availableY / (cardHeight + extra))
	local stackScale = math.min(availableX / stackWidth, availableY / (stackHeight + extra))
	local stacked = stackScale > wideScale
	local faceHeight = if stacked then C.StackedFaceHeight else cardHeight
	local columnsWidth = if stacked then stackWidth else wideWidth
	local columnsHeight = if stacked then stackHeight else cardHeight
	view.holder.Size = UDim2.fromOffset(columnsWidth, columnsHeight + extra)
	if stacked then
		view.face.Position = UDim2.fromOffset((stackWidth - C.FaceWidth) / 2, 0)
		view.card.Position = UDim2.fromOffset((stackWidth - C.RewardsWidth) / 2, faceHeight + gap)
	else
		view.face.Position = UDim2.fromOffset(0, 0)
		view.card.Position = UDim2.fromOffset(C.FaceWidth + gap, 0)
	end
	if view.choices then
		view.choices.root.Position = UDim2.fromOffset(0, columnsHeight + C.ChoicesGap)
		view.choices:layout(columnsWidth)
	end
	local scale = math.max(0.1, math.min(C.MaxScale, if stacked then stackScale else wideScale))
	view.fit.Scale = scale
	-- Small words are measured as drawn at this scale (drawnPx): once more with it (at most
	-- once).
	local textScale = math.min(1, scale)
	if not settled and textScale ~= (view.textScale or 1) then
		view.textScale = textScale
		self:layout(true)
		return
	end
	view.face.Size = UDim2.fromOffset(C.FaceWidth, faceHeight)
	view.card.Size = UDim2.fromOffset(C.RewardsWidth, cardHeight)

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
	if view.noUlts then
		local U = Config.UI.Ults
		local words = TextService:GetTextSize(
			Strings.Ults.Hud.NoUlts,
			U.NoUltsTextPx,
			(Enum.Font :: any)[K.Font],
			Vector2.new(1000, 100)
		).X
		view.noUlts.Position =
			UDim2.fromOffset(sideWidth + C.VsWidth / 2, portraitTop + size / 2 + C.VsTextPx / 2 + 6)
		view.noUlts.Size = UDim2.fromOffset(words + U.NoUltsPadPx * 2, U.ResultNoUltsHeightPx)
	end
end

--------------------------------------------------------------------------------------------
-- Showing, step by step
--------------------------------------------------------------------------------------------

-- The money a summary adds that has not flown in yet: the match bonus, the streak bonus and
-- the rank reward (all paid at the end, not live).
local function newMoneyOf(summary: any): number
	local m = if type(summary.money) == "table" then summary.money else {}
	return clean(m.bonus) + clean(m.streak) + clean(m.reward)
end

-- The screen's clock: seconds since it opened, plus any skip.
local function clock(view: any): number
	return os.clock() - view.started + view.offset
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
	-- Only the match and streak bonuses and the rank reward are new money here (the pots
	-- already flew in during play): the HUD waits for them from now and they land with the
	-- total chip.
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
	ScreenBlur.set(self, true)
	TweenService:Create(
		view.backdrop,
		TweenInfo.new(K.Motion.PopSeconds, Enum.EasingStyle.Quad),
		{ BackgroundTransparency = C.BackdropTransparency }
	):Play()
	UIAnim.popIn(view.stage)
	self:bind()
	view.loop = RunService.RenderStepped:Connect(function()
		local ok, err = pcall(self.step, self, false)
		if not ok then
			warn("[8ball] ResultScreen: " .. tostring(err))
			self:close()
		end
	end)
end

-- A and B skip or continue while the screen is up (not once the rematch row is up).
function ResultScreen.bind(self: any)
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
	elseif not view.choices and os.clock() - view.skippedAt >= C.SkipGuardSeconds then
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
	local rising = true -- XP is never lost: the bar only fills
	if t >= C.XpAt then
		if not view.delta.Visible then
			UIAnim.popIn(view.delta)
		end
		-- The boost chips follow the gain, one after another.
		for i, boost in view.boosts do
			if not boost.root.Visible and t >= C.XpAt + i * C.BoostStagger then
				UIAnim.popIn(boost.root)
			end
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
				flashing = s.crosses
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
	view.barFill.BackgroundColor3 = if flashing and math.floor(t * 12) % 2 == 0
		then tone("White")
		else tone("Gold")
	if moving and not quiet and os.clock() - view.lastXpTick >= C.XpTickEvery then
		view.lastXpTick = os.clock()
		local pitch = Config.Audio.XpTickPitch
		UISound.play("XpTick", pitch.From + (pitch.To - pitch.From) * fill)
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

-- The win's block flies into the hotbar (or the column's Inventory tile) once; its chip
-- bounces.
function ResultScreen.flyBlock(self: any, view: any)
	local chip = view.blockChip
	if not chip or view.blockFlown then
		return
	end
	view.blockFlown = true
	chip.root.Visible = true
	UIAnim.bounce(chip.root)
	RewardChips.fly(self.screen, chip, self.deps, "Inventory", 0)
end

-- The win's block at time t: the chip pops, then its block flies.
function ResultScreen.stepBlock(self: any, view: any, t: number)
	if t < view.blockAt then
		return
	end
	local chip = view.blockChip
	if chip and not chip.root.Visible and not view.blockFlown then
		UIAnim.popIn(chip.root)
	end
	if chip and t >= view.blockFlyAt then
		self:flyBlock(view)
	end
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
	self:stepBlock(view, t)
	if t >= view.continueAt and not view.continueShown then
		view.continueShown = true
		if view.choices then
			-- The row stays until a choice is made; a new rank shows over it now, not after.
			-- A and B are Roblox's own again: A presses the selected choice.
			ContextActionService:UnbindAction(ACTION)
			local first = view.choices:first()
			if isGamepad() and first then
				GuiService.SelectedObject = first
			end
			self:showRank(view)
		else
			UIAnim.popIn(view.continue)
			if isGamepad() then
				GuiService.SelectedObject = view.continue
			end
		end
	end
	if not view.choices and t >= view.continueAt + C.AutoCloseSeconds then
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
	-- Money the HUD is still waiting for lands now (the chip did not get to fly); the win's
	-- block still flies home, from where its chip is as the screen goes.
	if view.owed then
		view.owed = false
		payBack(self.money, view.newMoney)
	end
	self:flyBlock(view)
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(view.root) then
		GuiService.SelectedObject = nil
	end
	TweenService:Create(
		view.backdrop,
		TweenInfo.new(K.Motion.OutSeconds, Enum.EasingStyle.Quad),
		{ BackgroundTransparency = 1 }
	):Play()
	ScreenBlur.set(self, false)
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
	ScreenBlur.set(self, false)
	if not self.alive then
		return
	end
	self:showRank(view)
	if view.onDone then
		task.spawn(view.onDone)
	end
	local nextOne = table.remove(self.queue, 1)
	if nextOne then
		self:open(nextOne.summary, nextOne.onDone)
	end
end

-- NEW RANK! when the match took the player to a new division, once, with its rewards as chips
-- (the money only shows: it came in with this screen's total chip).
function ResultScreen.showRank(self: any, view: any)
	local xp = view.xp
	if view.rankShown or not self.newRank or not xp then
		return
	end
	if xp.promoted == true then
		view.rankShown = true
		self.newRank:show({
			kind = "Up",
			before = xp.before,
			after = xp.after,
			reward = clean(xp.rewardTotal),
			newTier = xp.newTier == true,
			rewards = xp.rewards,
			rewardBlocks = xp.rewardBlocks,
			rewardCues = xp.rewardCues,
			preview = view.summary.preview == true,
			paid = true, -- its money already came in with this screen's total chip
			held = xp.held == true, -- claimed in Rank (the tutorial lane)
		})
	end
end

--- Who presses the choices row's buttons: `fn(kind, summary)` (Main, through Progression).
--- Keep the next screens in the top part of the screen (true while the 1v1 result cutscene
--- shows the two players below it; GUI lane).
function ResultScreen.setLifted(self: any, lifted: boolean)
	self.lifted = lifted
	if self.view then
		self:layout()
	end
end

function ResultScreen.setChoiceHandler(self: any, fn: ((string, any) -> ())?)
	self.onChoice = fn
end

--- The summary whose choices row is up, or nil.
function ResultScreen.choosing(self: any): any?
	local view = self.view
	if view and view.choices and not view.closing then
		return view.summary
	end
	return nil
end

--- Draw the choices row's state (PostMatch.State) at server time `now`.
function ResultScreen.setChoices(self: any, state: any, now: number)
	local view = self.view
	if not view or not view.choices or view.closing then
		return
	end
	view.choices:set(state, now)
	-- A selection left on a button that just greyed out moves to one that works; none at all
	-- (NEW RANK! over the row just closed and let go of it) lands on the row's first button.
	local selected = GuiService.SelectedObject
	if view.continueShown and isGamepad() and not self:covered() then
		local lost = selected == nil
			or (selected:IsDescendantOf(view.root) and not selected.Selectable)
		if lost then
			local first = view.choices:first()
			if first then
				GuiService.SelectedObject = first
			end
		end
	end
end

-- Whether a popup over this screen has the gamepad now (NEW RANK!).
function ResultScreen.covered(self: any): boolean
	return self.newRank ~= nil and self.newRank:isOpen()
end

--- The choosing is over (a rematch began, the player is on their way): close the screen.
function ResultScreen.endChoices(self: any)
	if self.view and self.view.choices then
		self:close()
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
