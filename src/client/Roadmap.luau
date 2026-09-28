--!strict
-- Roadmap: the ranked screen (docs/prompts/RANKS_MONEY_PROMPT.md section 12, reference
-- 03-ranked-roadmap; laid out again by the designer 2026-09-27). Pressing the rank HUD opens
-- it: a big white kit panel over a dim backdrop with the trophy, "Ranked", a short subtitle
-- and a red close X; the ten tiers side by side; your rank's card and the chosen tier's
-- rewards card under them (no line of rules under them: designer, 2026-09-27).
--
-- The tier row, Bronze to Reyes: each tier's badge (its division I; yours shows your own
-- division), its name and a dot per division, gold for those reached. Your tier is bigger and
-- wider, over turning gold rays, with the shining badge, "Gold III" and a blue Current Rank tag;
-- the next tier breathes under a grey Next Rank tag; tiers past it are greyed and see-through.
-- As many tiers show as fit (fewer on a phone). Round < and > buttons at the ends scroll one
-- tier; it swipes on a touch screen and drags or wheels with a mouse. It opens centred on your
-- tier (Bronze when Unranked, with no tier yours).
--
-- Tapping a tier (or A on it) chooses it: a gold outline, and the rewards card shows what the
-- tier gives the first time you reach it: its money, a case and a cue (not given yet: Soon),
-- and its chat tag, drawn as chat draws it (ChatTags). It opens on your next tier. Rewards you
-- already have show a check. The rank card shows your badge, rank and XP bar, and an arrow to
-- your next division with the money it pays (only the first time you reach it).
--
-- States come from the local player's attributes (RankXp, RatedMatches, PeakDivision); any
-- change redraws the map. Gamepad: left and right move along the tiers and onto the arrows at
-- the ends, A chooses, up or down reaches the close X, B closes. Every size comes from the
-- screen: on a phone the panel takes the whole screen, its title in Roblox's top bar row
-- right of Roblox's buttons; on a computer it is capped. Numbers are in
-- Config.UI.Progress.Roadmap, words in Strings.Progress.
--
-- It lives in its own ScreenGui just over the HUD's (the rank and money HUDs have theirs), so
-- the backdrop covers them. Built on first open and kept; every loop runs only while open.
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
local Progression = Shared:WaitForChild("Progression")
local Format = require(Progression:WaitForChild("Format"))
local Ranks = require(Progression:WaitForChild("Ranks"))
local ChatTags = require(script.Parent.ChatTags)
local HudParts = require(script.Parent.HudParts)
local RankBadge = require(script.Parent.RankBadge)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

type Rank = Ranks.Rank

local R = Config.UI.Progress.Roadmap
local K = Config.UI.Kit
local P = Strings.Progress
local FONT: Enum.Font = (Enum.Font :: any)[K.Font]
local color = HudParts.color
local tone = HudParts.tone
local WHITE = tone("White")
local INK = tone("Ink")
local GOLD = tone("Gold")
local TIERS: { string } = Config.Ranks.Tiers
local TOP_TIER = TIERS[#TIERS]
local PER_TIER: number = Config.Ranks.DivisionsPerTier
local TIER_COLORS: { [string]: { number } } = Config.Ranks.Colors :: any
-- Each tier's division I reward row (ECONOMY 4.8): Money, Cases, Cue.
local TIER_REWARDS: { [string]: { Money: number } } = Config.Ranks.Rewards.Tier :: any
local ICONS: { [string]: string } = K.Icons :: any
-- The case and chat-tag icons (tools/gen_ui_art.py: case, chat_tag); stand-ins from the set
-- until their ids are in Config.UI.Kit.Icons.
local CASE_ICON = if ICONS.Case then "Case" else "Trophy"
local CHAT_ICON = if ICONS.ChatTag then "ChatTag" else "People"
local QUICK = Config.Multiplayer.Style.QuickMotion
local CLOSE_ACTION = "8ballRoadmapClose"
-- The save's rank as the server replicates it (PlayerData); any change redraws the map.
local WATCHED = { "RankXp", "RatedMatches", "PeakDivision", "RankIndex" }

type Cell = {
	order: number, -- the tier's place, 1..#TIERS
	tier: string,
	button: TextButton, -- the whole cell: tap, click or A chooses the tier
	body: Frame, -- everything in it, popped by hover and press
	hover: UIScale,
	ring: Frame, -- the gold outline: chosen (solid, with a pale fill), or hovered and focused
	ringEdge: UIStroke,
	ringCorner: UICorner,
	art: Frame, -- the badge's holder (breathes on the next tier)
	image: ImageLabel, -- the still badge (your tier shows the shining RankBadge instead)
	name: TextLabel,
	dotRow: Frame,
	dots: { Frame },
	x: number, -- left edge, in the row's canvas pixels
	w: number,
	lit: boolean,
	tween: Tween?,
}

type Tile = {
	frame: Frame,
	corner: UICorner,
	icon: ImageLabel,
	value: TextLabel,
	label: TextLabel?, -- the small word under the value (the cue has none: its name may wrap)
	check: ImageLabel, -- a reward you already have
	soon: Frame?, -- a reward not given yet
	soonWords: TextLabel?,
}

type Tiles = { money: Tile, case: Tile, chat: Tile, cue: Tile }

-- The local player's rank, read from their attributes.
type State = {
	rank: Rank,
	order: number, -- your tier's place, 1..#TIERS (0: Unranked)
	peak: number, -- the best division ever reached (its money is paid)
	fraction: number, -- how far into your division
	xpWords: string, -- "250 / 1,000 XP"
}

-- The panel's rows, measured from the screen.
type Geo = {
	t: number, -- 0 on a phone-sized panel, 1 on a full-size one
	gap: number,
	heading: number,
	body: number,
	rowW: number,
	rowH: number,
	leftW: number,
	rightW: number,
	cardsH: number,
}

-- The rank card's next-division line, measured (Roadmap.measureNext).
type NextLine = {
	top: boolean, -- you are at the top: just the words
	words: string,
	badgeImage: string,
	pays: boolean, -- its money is still to be paid (the chip shows)
	amountWords: string,
	gapX: number,
	arrow: number,
	badge: number,
	showBadge: boolean,
	textW: number,
	chipH: number,
	chipW: number,
	cash: number,
	cashX: number,
	amountX: number,
	amountW: number,
	fits: boolean, -- the words fit on one line
}

-- The tier row as last laid out.
type Row = {
	viewW: number, -- the visible part between the arrows
	canvasW: number,
}

export type Roadmap = {
	open: (self: Roadmap) -> (),
	close: (self: Roadmap) -> (),
	isOpen: (self: Roadmap) -> boolean,
	destroy: (self: Roadmap) -> (),
}

local Roadmap = {}
Roadmap.__index = Roadmap

--------------------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------------------

local function round(n: number): number
	return math.floor(n + 0.5)
end

-- A { phone, full } pair at t (0 a phone-sized panel, 1 a full one).
local function lerp(pair: { number }, t: number): number
	return pair[1] + (pair[2] - pair[1]) * t
end

local function spanPx(pair: { number }, t: number): number
	return round(lerp(pair, t))
end

local function textWidth(text: string, size: number): number
	return TextService:GetTextSize(text, size, FONT, Vector2.new(4000, 400)).X
end

local function tierColor(tier: string): Color3
	return color(TIER_COLORS[tier] or TIER_COLORS.Unranked)
end

local function circle(parent: Instance)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = parent
end

local function stroke(parent: Instance, tint: Color3, thickness: number): UIStroke
	local edge = Instance.new("UIStroke")
	edge.Name = "Edge"
	edge.Color = tint
	edge.Thickness = thickness
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = parent
	return edge
end

local function isGamepad(kind: Enum.UserInputType): boolean
	return string.sub(kind.Name, 1, 7) == "Gamepad"
end

local function readNumber(player: Player?, name: string): number
	local value = if player then player:GetAttribute(name) else nil
	return if type(value) == "number" and value == value then value else 0
end

-- "Gold IV", "Platinum I", "Reyes".
local function divisionName(tier: string, division: number): string
	return Ranks.name({
		tier = tier,
		division = division,
		index = Ranks.indexOf(tier, division) or 0,
		xpInDivision = 0,
		width = nil,
	})
end

local function readState(player: Player?): State
	local rated = readNumber(player, "RatedMatches") > 0
	local rank: Rank = Ranks.fromXp(readNumber(player, "RankXp"), rated)
	local peak =
		math.clamp(math.floor(readNumber(player, "PeakDivision")), rank.index, Ranks.count())
	local fraction = 0
	local xpWords: string
	local width = rank.width
	if rank.index == 0 then
		xpWords = Strings.Ranks.XpOf:format(Format.xp(0), Format.xp(Ranks.width(1) or 0))
	elseif width then
		fraction = math.clamp(rank.xpInDivision / width, 0, 1)
		xpWords = Strings.Ranks.XpOf:format(Format.xp(rank.xpInDivision), Format.xp(width))
	else
		fraction = 1 -- Reyes has no top
		xpWords = Strings.Ranks.XpOnly:format(Format.xp(rank.xpInDivision))
	end
	return {
		rank = rank,
		order = Ranks.tierIndex(rank.tier) or 0,
		peak = peak,
		fraction = fraction,
		xpWords = xpWords,
	}
end

-- The tier the rewards card opens on: the next one (Bronze when Unranked; Reyes at the top).
local function defaultTier(state: State): string
	return TIERS[math.min(state.order + 1, #TIERS)]
end

-- A clear button that swallows presses: the backdrop (which closes) and the panel's floor
-- (so a press on the panel's empty parts does not reach the backdrop).
local function catcher(parent: Instance, name: string): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = ""
	button.AutoButtonColor = false
	button.Selectable = false
	button.BorderSizePixel = 0
	button.BackgroundTransparency = 1
	button.Size = UDim2.fromScale(1, 1)
	button.Parent = parent
	return button
end

-- An XP bar: a round track with an ink edge and a gold fill.
local function makeBar(parent: Instance, name: string): (Frame, Frame)
	local track = HudParts.frame(parent, name)
	track.BackgroundTransparency = 0
	track.BackgroundColor3 = color(R.BarBackColor)
	track.ZIndex = 2
	circle(track)
	stroke(track, INK, 2)
	local fill = HudParts.frame(track, "Fill")
	fill.BackgroundTransparency = 0
	fill.BackgroundColor3 = WHITE
	fill.Size = UDim2.fromScale(0, 1)
	circle(fill)
	local shade = Instance.new("UIGradient")
	shade.Rotation = 90
	shade.Color = ColorSequence.new(color(R.BarTopColor), GOLD)
	shade.Parent = fill
	return track, fill
end

-- A small round tag with words (Current Rank, Next Rank, Soon), hung by its bottom middle.
-- Its words keep one line at their set size; the tag is sized from them.
local function makeTag(
	parent: Instance,
	name: string,
	tint: Color3,
	words: string
): (Frame, TextLabel)
	local tag = HudParts.pill(parent, name, tint)
	tag.AnchorPoint = Vector2.new(0.5, 1)
	local label = HudParts.text(tag, "Words", K.Text.Body, words)
	label.TextWrapped = false
	label.Size = UDim2.fromScale(1, 1)
	return tag, label
end

-- Tween a cell's scale back to where it rests (up while lit), from `from` if given.
local function settleCell(cell: Cell, from: number?, seconds: number)
	if cell.tween then
		cell.tween:Cancel()
	end
	if from then
		cell.hover.Scale = from
	end
	local tween = TweenService:Create(
		cell.hover,
		TweenInfo.new(seconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = if cell.lit then R.HoverScale else 1 }
	)
	cell.tween = tween
	tween:Play()
end

-- The arrow buttons' glyph: a white chevron image with an ink outline, drawn as one stroke
-- so its tip is a single clean joint (four rotated bars left a seam there, 2026-09-27).
local function makeChevron(parent: Instance, dir: number): ImageLabel
	local chevron =
		HudParts.icon(parent, if dir < 0 then "ChevronLeft" else "ChevronRight", "Chevron")
	chevron.AnchorPoint = Vector2.new(0.5, 0.5)
	chevron.ZIndex = 2
	return chevron
end

--------------------------------------------------------------------------------------------
-- Building (once, on the first open)
--------------------------------------------------------------------------------------------

--- A roadmap for the local player. `screen` is the shared HUD ScreenGui: the map makes its
--- own ScreenGui beside it, just above it. Nothing is built until the first open.
function Roadmap.new(screen: ScreenGui): Roadmap
	local self: any = setmetatable({}, Roadmap)
	self.screen = screen
	self.player = Players.LocalPlayer
	self.alive = true
	self.opened = false
	self.built = false
	self.connections = {} -- for the map's life
	self.openConnections = {} -- only while open
	self.bound = false
	self.geo = nil :: Geo?
	self.row = nil :: Row?
	self.state = nil :: State?
	self.selected = nil :: string? -- the tier the rewards card shows
	self.focusCell = nil -- the last tier a gamepad was on (the close X leads back to it)
	self.scrollTarget = nil -- a canvas X the row is gliding to
	self.holdUntil = 0 -- the row is held on its target until then (the opening pop)
	self.drag = nil -- a mouse drag of the row
	self.dragMoved = false -- the last press dragged (so its release is not a press)
	self.refreshQueued = false
	self.arrowFaded = {} -- per arrow button: faded at the row's end
	self.pulse = nil
	self.pulseCell = nil
	self.spinner = nil
	self.stepper = nil
	self.dimTween = nil
	self.barTween = nil
	self.nudgeTween = nil
	self.previousSelection = nil
	return self :: Roadmap
end

-- One tier in the row: a selectable button holding the badge, the name, the division dots
-- and the gold ring.
local function makeCell(self: any, order: number, tier: string): Cell
	local button = Instance.new("TextButton")
	button.Name = tier
	button.Text = ""
	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.Selectable = true
	button.SelectionImageObject = self.noBox
	local body = HudParts.frame(button, "Body")
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	body.Position = UDim2.fromScale(0.5, 0.5)
	body.Size = UDim2.fromScale(1, 1)
	local hover = Instance.new("UIScale")
	hover.Name = "Hover"
	hover.Parent = body
	local ring = HudParts.frame(body, "Ring")
	ring.BackgroundColor3 = GOLD
	ring.ZIndex = 1
	ring.Visible = false
	local ringCorner = Instance.new("UICorner")
	ringCorner.Parent = ring
	local ringEdge = stroke(ring, GOLD, R.RingPx)
	local art = HudParts.frame(body, "Art")
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.ZIndex = 2
	local image = Instance.new("ImageLabel")
	image.Name = "Badge"
	image.BackgroundTransparency = 1
	image.ScaleType = Enum.ScaleType.Fit
	image.Image = RankBadge.image(tier, 1)
	image.Size = UDim2.fromScale(1, 1)
	image.Parent = art
	local name = HudParts.text(body, "Name", K.Text.Body, Ranks.tierName(tier))
	name.AnchorPoint = Vector2.new(0.5, 0)
	name.ZIndex = 3
	local dotRow = HudParts.frame(body, "Dots")
	dotRow.AnchorPoint = Vector2.new(0.5, 0)
	dotRow.ZIndex = 3
	local dots: { Frame } = {}
	for i = 1, if tier == TOP_TIER then 1 else PER_TIER do
		local dot = HudParts.frame(dotRow, "Dot" .. i)
		dot.BackgroundTransparency = 0
		circle(dot)
		stroke(dot, INK, R.DotStrokePx)
		table.insert(dots, dot)
	end
	button.Parent = self.cellLayer
	local cell: Cell = {
		order = order,
		tier = tier,
		button = button,
		body = body,
		hover = hover,
		ring = ring,
		ringEdge = ringEdge,
		ringCorner = ringCorner,
		art = art,
		image = image,
		name = name,
		dotRow = dotRow,
		dots = dots,
		x = 0,
		w = 0,
		lit = false,
		tween = nil,
	}
	button.MouseEnter:Connect(function()
		if UserInputService:GetLastInputType() ~= Enum.UserInputType.Touch then
			self:lightCell(cell, true)
		end
	end)
	button.MouseLeave:Connect(function()
		self:lightCell(cell, false)
	end)
	button.SelectionGained:Connect(function()
		self.focusCell = cell
		self.closeButton.NextSelectionDown = button
		self:lightCell(cell, true)
		self:scrollToCell(cell)
	end)
	button.SelectionLost:Connect(function()
		self:lightCell(cell, false)
	end)
	button.Activated:Connect(function()
		if not self.dragMoved then
			UISound.play("Click")
			self:choose(tier, true)
			self:revealCell(cell)
			settleCell(cell, R.PressScale, R.PressSeconds)
		end
	end)
	return cell
end

-- One reward tile: a white rounded tile with the icon over the value and a small word, a
-- check once you have it, and a yellow Soon tag on a reward not given yet.
local function makeTile(
	parent: Instance,
	name: string,
	iconKey: string,
	words: string?,
	soon: boolean
): Tile
	local frame = HudParts.frame(parent, name)
	frame.BackgroundTransparency = 0
	frame.BackgroundColor3 = WHITE
	local corner = Instance.new("UICorner")
	corner.Parent = frame
	stroke(frame, color(R.TileEdgeColor), R.TileStrokePx)
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Color = ColorSequence.new(WHITE, color(K.PanelFade))
	fade.Parent = frame
	local icon = HudParts.icon(frame, iconKey, "Icon")
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.ZIndex = 2
	local value = HudParts.text(frame, "Value", K.Text.Body, "")
	value.ZIndex = 2
	local label = if words then HudParts.note(frame, "Label", K.Text.Body, words) else nil
	if label then
		label.ZIndex = 2
	end
	local check = HudParts.icon(frame, "Check", "Check")
	check.AnchorPoint = Vector2.new(1, 0)
	check.ZIndex = 3
	check.Visible = false
	local tag: Frame?, tagWords: TextLabel? = nil, nil
	if soon then
		local made, madeWords = makeTag(frame, "Soon", GOLD, P.Soon)
		made.AnchorPoint = Vector2.new(1, 0)
		made.ZIndex = 4
		tag, tagWords = made, madeWords
	end
	return {
		frame = frame,
		corner = corner,
		icon = icon,
		value = value,
		label = label,
		check = check,
		soon = tag,
		soonWords = tagWords,
	}
end

function Roadmap.buildHeader(self: any, card: Frame)
	local header = HudParts.frame(card, "Header")
	self.header = header
	self.trophy = HudParts.icon(header, "Trophy", "Trophy")
	local title = HudParts.text(header, "Title", K.Text.Title, P.RankedTitle)
	title.TextWrapped = false
	title.TextXAlignment = Enum.TextXAlignment.Left
	self.title = title
	local subtitle = HudParts.note(header, "Subtitle", K.Text.Body, P.RankedSubtitle)
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	self.subtitle = subtitle
	local close = HudParts.candy(header, "", function()
		UISound.play("Click")
		self:close()
	end, "Red", "X")
	close.Name = "Close"
	HudParts.setMinHit(close, R.TouchMinPx)
	self.closeButton = close
end

-- A round blue candy arrow at one end of the tier row: each press scrolls one tier.
function Roadmap.makeArrow(self: any, parent: Instance, dir: number): (TextButton, ImageLabel)
	local button = HudParts.candy(parent, "", function()
		UISound.play("Click")
		self:stepRow(dir)
	end, "Blue", nil)
	button.Name = if dir < 0 then "Back" else "Forward"
	local parts = HudParts.candyParts(button)
	local corner = parts.face:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0.5, 0)
	end
	return button, makeChevron(parts.body, dir)
end

function Roadmap.buildRow(self: any, card: Frame)
	local area = HudParts.frame(card, "TierRow")
	self.rowArea = area
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Tiers"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Selectable = false
	scroll.ScrollingDirection = Enum.ScrollingDirection.X
	scroll.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
	scroll.ScrollBarThickness = 0 -- the arrows show there is more
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.Parent = area
	self.scroll = scroll
	-- Gold rays turning behind your badge, under every tier.
	local glowLayer = HudParts.frame(scroll, "Glow")
	glowLayer.ZIndex = 1
	self.glowLayer = glowLayer
	local glow = Instance.new("ImageLabel")
	glow.Name = "Rays"
	glow.BackgroundTransparency = 1
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Image = K.Art.Rays
	glow.ImageColor3 = GOLD
	glow.ImageTransparency = R.GlowTransparency
	glow.Visible = false
	glow.Parent = glowLayer
	self.glow = glow
	local cellLayer = HudParts.frame(scroll, "Cells")
	cellLayer.ZIndex = 2
	self.cellLayer = cellLayer
	self.cells = {} :: { Cell }
	for order, tier in TIERS do
		table.insert(self.cells, makeCell(self, order, tier))
	end
	-- The tags (moved into your tier and the next one) and the shining badge in yours.
	self.currentTag, self.currentTagWords =
		makeTag(cellLayer, "CurrentTag", tone("Blue"), P.CurrentRank)
	self.currentTag.ZIndex = 4
	self.nextTag, self.nextTagWords =
		makeTag(cellLayer, "NextTag", color(R.NextTagColor), P.NextRank)
	self.nextTag.ZIndex = 4
	local badge = RankBadge.new(cellLayer, { size = 64, interactive = false, name = "YourBadge" })
	badge.root.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.root.Position = UDim2.fromScale(0.5, 0.5)
	self.rowBadge = badge
	self.backArrow, self.backChevron = self:makeArrow(area, -1)
	self.forwardArrow, self.forwardChevron = self:makeArrow(area, 1)
end

function Roadmap.buildRankCard(self: any, card: Frame)
	local rankCard = HudParts.card(card, "RankCard")
	self.rankCard = rankCard
	local fill = rankCard:FindFirstChild("Fill")
	self.rankFade = if fill then fill:FindFirstChildOfClass("UIGradient") else nil
	local holder = HudParts.frame(rankCard, "BadgeHolder")
	holder.ZIndex = 2
	self.rankBadgeHolder = holder
	self.rankBadge = RankBadge.new(holder, { size = 64, interactive = false, name = "Badge" })
	local name = HudParts.text(rankCard, "RankName", K.Text.Heading, "")
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.ZIndex = 2
	self.rankName = name
	local label = HudParts.note(rankCard, "CurrentRank", K.Text.Body, P.CurrentRank)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 2
	self.rankLabel = label
	self.rankBar, self.rankFill = makeBar(rankCard, "XpBar")
	local xp = HudParts.note(rankCard, "Xp", K.Text.Body, "")
	xp.TextXAlignment = Enum.TextXAlignment.Left
	xp.ZIndex = 2
	self.rankXp = xp
	-- The next division: an arrow, its badge, "Next: Gold IV" and the money it pays.
	local nextRow = HudParts.frame(rankCard, "Next")
	nextRow.ZIndex = 2
	self.nextRow = nextRow
	self.nextArrow = HudParts.icon(nextRow, "Arrow", "Arrow")
	local nextBadge = Instance.new("ImageLabel")
	nextBadge.Name = "Badge"
	nextBadge.BackgroundTransparency = 1
	nextBadge.ScaleType = Enum.ScaleType.Fit
	nextBadge.Parent = nextRow
	self.nextBadge = nextBadge
	local words = HudParts.text(nextRow, "Words", K.Text.Body, "")
	words.TextXAlignment = Enum.TextXAlignment.Left
	self.nextLine = words
	local chip = HudParts.pill(nextRow, "Chip", WHITE)
	self.chip = chip
	local cash = HudParts.icon(chip, "CashSingle", "Cash")
	cash.AnchorPoint = Vector2.new(0, 0.5)
	cash.ZIndex = 2
	self.chipCash = cash
	local amount = HudParts.text(chip, "Amount", K.Text.Body, "")
	amount.AutoLocalize = false -- a number
	amount.ZIndex = 2
	self.chipAmount = amount
	local help = HudParts.note(rankCard, "Help", K.Text.Body, P.EarnXp)
	help.TextXAlignment = Enum.TextXAlignment.Left
	help.ZIndex = 2
	self.help = help
end

function Roadmap.buildRewards(self: any, card: Frame)
	local rewards = HudParts.card(card, "RewardsCard")
	self.rewardsCard = rewards
	local title = HudParts.text(rewards, "Title", K.Text.Heading, "")
	title.TextXAlignment = Enum.TextXAlignment.Left
	self.rewardsTitle = title
	local holder = HudParts.frame(rewards, "Tiles")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	self.tileHolder = holder
	local nudge = Instance.new("UIScale")
	nudge.Name = "Nudge"
	nudge.Parent = holder
	self.nudge = nudge
	local tiles: Tiles = {
		money = makeTile(holder, "Money", "CashStack", P.RewardMoney, false),
		case = makeTile(holder, "Case", CASE_ICON, P.RewardCount:format(1), true),
		chat = makeTile(holder, "ChatTag", CHAT_ICON, P.RewardChatTag, false),
		cue = makeTile(holder, "Cue", "Cue", nil, true),
	}
	tiles.money.value.AutoLocalize = false -- a number
	-- The tag exactly as chat shows it (RichText colours; Reyes letter by letter).
	tiles.chat.value.RichText = true
	tiles.chat.value.AutoLocalize = false
	tiles.cue.value.TextYAlignment = Enum.TextYAlignment.Top -- it may take two lines
	self.tiles = tiles
	self.tileOrder = { tiles.money, tiles.case, tiles.chat, tiles.cue }
end

-- Where a gamepad goes: along the tiers, onto the arrows at the ends, up or down to the close
-- X, and from the X back to the tier it came from. The panel is a selection group that stops
-- at its edges.
function Roadmap.link(self: any)
	local close = self.closeButton
	local cells: { Cell } = self.cells
	local count = #cells
	for order, cell in cells do
		local button = cell.button
		button.NextSelectionLeft = if order > 1 then cells[order - 1].button else self.backArrow
		button.NextSelectionRight = if order < count
			then cells[order + 1].button
			else self.forwardArrow
		button.NextSelectionUp = close
		button.NextSelectionDown = close
	end
	local back: TextButton = self.backArrow
	back.NextSelectionLeft = back
	back.NextSelectionRight = cells[1].button
	back.NextSelectionUp = close
	back.NextSelectionDown = close
	local forward: TextButton = self.forwardArrow
	forward.NextSelectionLeft = cells[count].button
	forward.NextSelectionRight = forward
	forward.NextSelectionUp = close
	forward.NextSelectionDown = close
	close.NextSelectionUp = close
	close.NextSelectionRight = close
	close.NextSelectionLeft = close
	close.NextSelectionDown = cells[1].button
end

function Roadmap.build(self: any)
	self.built = true
	local parent = self.screen.Parent
	-- Over the whole screen, Roblox's top bar row included, so the backdrop dims everything
	-- and a phone's panel can use that row. Coordinates stay shared with every ScreenGui.
	local gui = Instance.new("ScreenGui")
	gui.Name = "Roadmap"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets -- the top bar row, not a notch
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = self.screen.DisplayOrder + R.DisplayOrderAbove
	gui.Enabled = false
	gui.Parent = parent
	self.gui = gui
	-- The free part of Roblox's top bar (right of its buttons), as MatchHUD measures it.
	local probe = Instance.new("ScreenGui")
	probe.Name = "RoadmapTopbar"
	probe.ScreenInsets = Enum.ScreenInsets.TopbarSafeInsets
	probe.ResetOnSpawn = false
	probe.Parent = parent
	self.probe = probe
	local area = HudParts.frame(probe, "Area")
	area.Size = UDim2.fromScale(1, 1)
	self.topbarArea = area

	local root = HudParts.frame(gui, "Root")
	root.Size = UDim2.fromScale(1, 1)
	self.root = root
	-- An empty selection box: tiers draw their own gold ring, buttons their gold outline.
	local noBox = Instance.new("Frame")
	noBox.BackgroundTransparency = 1
	self.noBox = noBox
	local dim = catcher(root, "Backdrop")
	dim.BackgroundColor3 = INK
	dim.Activated:Connect(function()
		self:close()
	end)
	self.dim = dim

	local panel = HudParts.frame(root, "Panel")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.ZIndex = 2
	panel.Visible = false
	panel.SelectionGroup = true
	panel.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	panel.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	panel.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	panel.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
	self.panel = panel
	catcher(panel, "Floor").ZIndex = 0
	local card = HudParts.menuCard(panel, "Card")
	card.Size = UDim2.fromScale(1, 1)
	card.ZIndex = 1
	self.card = card
	self:buildHeader(card)
	self:buildRow(card)
	self:buildRankCard(card)
	self:buildRewards(card)
	self:link()

	local function resized()
		if self.opened and self:layout() then
			self:draw(false)
			self:centre(false)
		end
	end
	table.insert(self.connections, root:GetPropertyChangedSignal("AbsoluteSize"):Connect(resized))
	for _, property in { "AbsoluteSize", "AbsolutePosition" } do
		table.insert(self.connections, area:GetPropertyChangedSignal(property):Connect(resized))
	end
	table.insert(
		self.connections,
		self.scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			self:updateArrows()
		end)
	)
end

--------------------------------------------------------------------------------------------
-- Layout (from the screen's size; on open and when the screen changes)
--------------------------------------------------------------------------------------------

-- Roblox's top bar in the root's pixels: its free part's left and right edges and the row's
-- bottom (fallbacks when Roblox does not say).
function Roadmap.topbar(self: any, size: Vector2): (number, number, number)
	local area = self.topbarArea
	local probe = area and area.Parent
	if area and probe and probe.Parent and area.AbsoluteSize.Y > 0 then
		local origin = self.root.AbsolutePosition
		local left = area.AbsolutePosition.X - origin.X
		-- The root covers the whole screen (IgnoreGuiInset), so the row starts at its top or,
		-- on a phone whose screen starts lower than the inset says, a little below it.
		local top = math.max(0, area.AbsolutePosition.Y - origin.Y)
		return left, left + area.AbsoluteSize.X, top + area.AbsoluteSize.Y
	end
	return R.TopbarLeftFallbackPx, size.X, GuiService:GetGuiInset().Y
end

function Roadmap.layoutHeader(
	self: any,
	width: number,
	height: number,
	left: number,
	right: number,
	gap: number,
	titleSize: number,
	body: number,
	oneRow: boolean
)
	local closeSize = math.min(height, R.CloseMaxPx)
	local close = self.closeButton
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.Size = UDim2.fromOffset(closeSize, closeSize)
	close.Position = UDim2.fromOffset(width - right, round(height / 2))
	local trophy = math.min(height, round(titleSize * 1.5))
	self.trophy.Size = UDim2.fromOffset(trophy, trophy)
	self.trophy.Position = UDim2.fromOffset(left, round((height - trophy) / 2))
	HudParts.setTextSize(self.title, titleSize)
	HudParts.setTextSize(self.subtitle, body)
	local titleX = left + trophy + gap
	local titleW = math.ceil(textWidth(P.RankedTitle, titleSize)) + 8
	local room = width - right - closeSize - gap -- where words must end
	if oneRow then
		-- A phone: the subtitle beside the title (on two lines if it must).
		self.title.Position = UDim2.fromOffset(titleX, 0)
		self.title.Size = UDim2.fromOffset(math.max(1, math.min(titleW, room - titleX)), height)
		local subX = titleX + titleW + gap
		self.subtitle.Visible = room - subX >= R.SubtitleMinPx
		self.subtitle.Position = UDim2.fromOffset(subX, 0)
		self.subtitle.Size = UDim2.fromOffset(math.max(1, room - subX), height)
	else
		local titleH = titleSize + 8
		local subH = body + 6
		local y = math.max(0, round((height - titleH - subH) / 2))
		self.title.Position = UDim2.fromOffset(titleX, y)
		self.title.Size = UDim2.fromOffset(math.max(1, math.min(titleW, room - titleX)), titleH)
		self.subtitle.Visible = true
		self.subtitle.Position = UDim2.fromOffset(titleX, y + titleH)
		self.subtitle.Size = UDim2.fromOffset(math.max(1, room - titleX), subH)
	end
end

--- Size and place the panel and its rows from the screen's size. A phone-sized screen gets
--- the whole screen, the title in Roblox's top bar row; a bigger one a capped panel below the
--- bar. False while the screen has no size yet.
function Roadmap.layout(self: any): boolean
	local size: Vector2 = self.root.AbsoluteSize
	if size.X < 1 or size.Y < 1 then
		return false
	end
	local barLeft, barRight, barBottom = self:topbar(size)
	local margin = R.MarginPx
	local short = size.Y - barBottom < R.ShortScreenPx
	local roomTop = if short then 0 else barBottom
	local roomHeight = size.Y - roomTop
	local w = math.floor(math.min(size.X - 2 * margin, R.MaxSizePx[1]))
	local h = math.floor(math.min(roomHeight - 2 * margin, R.MaxSizePx[2]))
	local left = math.floor((size.X - w) / 2)
	local top = math.floor(roomTop + (roomHeight - h) / 2)
	self.panel.Size = UDim2.fromOffset(w, h)
	self.panel.Position = UDim2.fromOffset(left + w / 2, top + h / 2)

	-- Rows run from their phone size to their full size as the panel grows.
	local k = math.clamp(h / R.DesignHeightPx, R.MinScale, 1)
	local t = (k - R.MinScale) / (1 - R.MinScale)
	local pad = spanPx(R.PaddingPx, t)
	local gap = spanPx(R.GapPx, t)
	local iw = w - 2 * pad
	local titleSize = round(K.Text.Title * R.TitleScale * k)
	local heading = math.max(K.Text.Min, round(K.Text.Heading * k))
	local body = math.max(K.Text.Min, round(K.Text.Body * k))

	-- The title row; on a phone it is Roblox's top bar row, right of Roblox's buttons.
	local headerH, headLeft, headRight = spanPx(R.HeaderPx, t), 0, 0
	if short then
		headerH = math.max(R.TouchMinPx, barBottom - top - pad)
		headLeft = math.max(0, barLeft - left - pad + gap)
		headRight = math.max(0, left + w - pad - barRight)
	end
	self.header.Position = UDim2.fromOffset(pad, pad)
	self.header.Size = UDim2.fromOffset(iw, headerH)
	self:layoutHeader(iw, headerH, headLeft, headRight, gap, titleSize, body, short)
	-- The header band is the title row; everything under it sits on the sheet.
	HudParts.setSheetTop(self.card, pad + headerH + round(gap / 2))

	-- Bottom up: the two cards, then the tier row takes the rest.
	local cardsH = spanPx(R.CardsPx, t)
	local cardsY = h - pad - cardsH
	local rightW = round((iw - gap) * lerp(R.RewardsShare, t))
	local leftW = iw - gap - rightW
	self.rankCard.Position = UDim2.fromOffset(pad, cardsY)
	self.rankCard.Size = UDim2.fromOffset(leftW, cardsH)
	self.rewardsCard.Position = UDim2.fromOffset(pad + leftW + gap, cardsY)
	self.rewardsCard.Size = UDim2.fromOffset(rightW, cardsH)
	local rowY = pad + headerH + gap
	local rowH = math.max(R.TouchMinPx * 2, cardsY - gap - rowY)
	self.rowArea.Position = UDim2.fromOffset(pad, rowY)
	self.rowArea.Size = UDim2.fromOffset(iw, rowH)
	local geo: Geo = {
		t = t,
		gap = gap,
		heading = heading,
		body = body,
		rowW = iw,
		rowH = rowH,
		leftW = leftW,
		rightW = rightW,
		cardsH = cardsH,
	}
	self.geo = geo
	return true
end

-- The tier row: as many tiers as fit side by side, yours bigger and wider; each tier's badge,
-- name and dots; the tags, the rays and your shining badge; the arrows at the ends.
function Roadmap.layoutRow(self: any)
	local geo: Geo = self.geo
	local state: State = self.state
	local t = geo.t
	local areaW, h = geo.rowW, geo.rowH
	local body, heading = geo.body, geo.heading
	local current = state.order
	local arrow = math.max(R.TouchMinPx, spanPx(R.ArrowPx, t))
	local side = arrow + geo.gap
	local viewW = math.max(1, areaW - 2 * side)

	-- Heights, from the tallest column (yours): its tag, badge, name and dots.
	local tagH = math.max(K.Text.Min + 6, spanPx(R.TagPx, t))
	local tagText = math.max(K.Text.Min, round(tagH * 0.7))
	local nameH, bigNameH = body + 4, heading + 4
	local dot = spanPx(R.DotPx, t)
	local bigDot = round(dot * R.CurrentScale)
	local stack = R.TagAboveShare + R.NameBelowShare
	local room = h - tagH - bigNameH - bigDot - 8
	local bc = math.floor(math.clamp(room / stack, R.TouchMinPx, R.BadgeMaxPx * R.CurrentScale))
	local b = math.floor(bc / R.CurrentScale)
	local used = tagH + bc * stack + bigNameH + 2 + bigDot
	local top = math.max(0, round((h - used) / 2))
	local cy = round(top + tagH + bc * R.TagAboveShare)

	-- Widths: as many tiers as fit (VisibleTiers), each wide enough for its badge, name and
	-- tag; yours CurrentCellScale wider.
	local pad = R.CellTextPadPx
	local widest = 0
	for _, tier in TIERS do
		widest = math.max(widest, textWidth(Ranks.tierName(tier), body))
	end
	local tagW = textWidth(P.CurrentRank, tagText) + tagH
	local nextTagW = textWidth(P.NextRank, tagText) + tagH
	local least = math.max(b * R.CellAspect, widest + pad, nextTagW + pad)
	local bigLeast = 0
	if current > 0 then
		bigLeast = math.max(textWidth(Ranks.name(state.rank), heading) + pad, tagW + pad)
	end
	local extra = if current > 0 then R.CurrentCellScale - 1 else 0
	local fewest, most = R.VisibleTiers[1], R.VisibleTiers[2]
	local shown = fewest
	for n = most, fewest, -1 do
		local each = viewW / (n + extra)
		if each >= least and each * R.CurrentCellScale >= bigLeast then
			shown = n
			break
		end
	end
	local w = viewW / (shown + extra)

	local ringTop = math.max(R.RingPx, top - 3)
	local ringBottom = math.min(h - R.RingPx, top + round(used) + 3)
	local ringCorner = UDim.new(0, round(R.RingCornerPx * (0.75 + 0.25 * t)))
	local x = 0
	for order, cell: Cell in self.cells do
		local mine = order == current
		local cw = if mine then w * R.CurrentCellScale else w
		local left, right = round(x), round(x + cw)
		x += cw
		local width = right - left
		local mid = round(width / 2)
		cell.x = left
		cell.w = width
		cell.button.Position = UDim2.fromOffset(left, 0)
		cell.button.Size = UDim2.fromOffset(width, h)
		cell.button.ZIndex = if mine then 2 else 1
		local size = if mine then bc else b
		cell.art.Size = UDim2.fromOffset(size, size)
		cell.art.Position = UDim2.fromOffset(mid, cy)
		cell.name.Text = if mine then Ranks.name(state.rank) else Ranks.tierName(cell.tier)
		HudParts.setTextSize(cell.name, if mine then heading else body)
		local nh = if mine then bigNameH else nameH
		local nameY = cy + round(size * R.NameBelowShare)
		cell.name.Position = UDim2.fromOffset(mid, nameY)
		cell.name.Size = UDim2.fromOffset(math.max(1, width - 4), nh)
		local d = if mine then bigDot else dot
		local spacing = math.max(2, round(d * R.DotGapShare))
		local count = #cell.dots
		cell.dotRow.Position = UDim2.fromOffset(mid, nameY + nh + 1)
		cell.dotRow.Size = UDim2.fromOffset(count * d + (count - 1) * spacing, d)
		for i, dotFrame in cell.dots do
			dotFrame.Size = UDim2.fromOffset(d, d)
			dotFrame.Position = UDim2.fromOffset((i - 1) * (d + spacing), 0)
		end
		cell.ring.Position = UDim2.fromOffset(R.RingPx + 1, ringTop)
		cell.ring.Size =
			UDim2.fromOffset(math.max(1, width - 2 * (R.RingPx + 1)), ringBottom - ringTop)
		cell.ringCorner.CornerRadius = ringCorner
	end
	local canvasW = round(x)

	-- Current Rank over yours, Next Rank over the next; the rays and the shining badge.
	local here: Cell? = self.cells[current]
	local nextCell: Cell? = self.cells[current + 1]
	HudParts.setTextSize(self.currentTagWords, tagText)
	HudParts.setTextSize(self.nextTagWords, tagText)
	self.currentTag.Visible = here ~= nil
	if here then
		self.currentTag.Parent = here.body
		self.currentTag.Size = UDim2.fromOffset(round(tagW), tagH)
		self.currentTag.Position =
			UDim2.fromOffset(round(here.w / 2), cy - round(bc * R.TagAboveShare))
	end
	self.nextTag.Visible = nextCell ~= nil
	if nextCell then
		self.nextTag.Parent = nextCell.body
		self.nextTag.Size = UDim2.fromOffset(round(nextTagW), tagH)
		self.nextTag.Position =
			UDim2.fromOffset(round(nextCell.w / 2), cy - round(b * R.TagAboveShare))
	end
	local glow = self.glow
	glow.Visible = here ~= nil and state.rank.tier ~= TOP_TIER -- Reyes' badge has its own rays
	if here then
		local glowSize = round(bc * R.GlowScale)
		glow.Size = UDim2.fromOffset(glowSize, glowSize)
		glow.Position = UDim2.fromOffset(here.x + round(here.w / 2), cy)
	end
	local badge = self.rowBadge
	badge.root.Visible = here ~= nil
	if here then
		badge.root.Parent = here.art
		badge:setSize(bc)
	end

	-- The window the tiers scroll in, between the arrows.
	self.scroll.Position = UDim2.fromOffset(side, 0)
	self.scroll.Size = UDim2.fromOffset(viewW, h)
	self.scroll.CanvasSize = UDim2.fromOffset(canvasW, 0)
	self.glowLayer.Size = UDim2.fromOffset(canvasW, h)
	self.cellLayer.Size = UDim2.fromOffset(canvasW, h)
	-- The arrows, their faces (above the candy's lip) level with the badges.
	local face = arrow * (1 - K.ButtonLipShare)
	local chevron = round(arrow * R.ChevronShare)
	local function placeArrow(button: TextButton, glyph: ImageLabel, atX: number)
		button.Size = UDim2.fromOffset(arrow, arrow)
		button.Position = UDim2.fromOffset(atX, cy - round(face / 2))
		glyph.Position = UDim2.fromOffset(round(arrow / 2), round(face / 2))
		glyph.Size = UDim2.fromOffset(chevron, chevron)
	end
	placeArrow(self.backArrow, self.backChevron, 0)
	placeArrow(self.forwardArrow, self.forwardChevron, areaW - arrow)
	local row: Row = { viewW = viewW, canvasW = canvasW }
	self.row = row
	local x0 = self:clampCanvas(self.scroll.CanvasPosition.X)
	self.scroll.CanvasPosition = Vector2.new(x0, 0)
end

-- Your rank's card: the badge, the name, Current Rank, the XP bar, the next division.
function Roadmap.drawRankCard(self: any, live: boolean, moved: boolean)
	local geo: Geo = self.geo
	local state: State = self.state
	local rank = state.rank
	local w, h = geo.leftW, geo.cardsH
	local body, heading = geo.body, geo.heading
	local p = math.max(4, round(h * R.CardPadShare))
	local inset = math.max(3, round(p * 0.6))
	local badge = round(h * R.RankBadgeShare)
	self.rankBadgeHolder.Size = UDim2.fromOffset(badge, badge)
	self.rankBadgeHolder.Position = UDim2.fromOffset(inset, round((h - badge) / 2))
	self.rankBadge:setSize(badge)
	self.rankBadge:set(rank.tier, rank.division, live and moved)
	local x = inset + badge + inset
	local colW = math.max(1, w - x - p)

	-- The lines that fit, top to bottom; the help line first to go, then Current Rank. The
	-- next-division line takes two lines when its words do not fit on one.
	local nameH, labelH, barRowH, helpH = heading + 4, body + 2, body + 4, body + 2
	local lineH = math.max(body + 8, round(h * R.NextRowShare))
	local nextLine = self:measureNext(colW, lineH, body)
	local nextH = if nextLine.fits then lineH else math.max(lineH, body * 2 + 8)
	local rowGap = math.max(2, round(h * 0.03))
	local inner = h - 2 * p
	local lines = nameH + labelH + barRowH + nextH + 3 * rowGap
	local showLabel = lines <= inner
	if not showLabel then
		lines -= labelH + rowGap
	end
	local showHelp = showLabel and lines + helpH + rowGap <= inner
	local total = lines + (if showHelp then helpH + rowGap else 0)
	local y = p + math.max(0, round((inner - total) / 2))

	HudParts.setTextSize(self.rankName, heading)
	self.rankName.Text = Ranks.name(rank)
	self.rankName.Position = UDim2.fromOffset(x, y)
	self.rankName.Size = UDim2.fromOffset(colW, nameH)
	y += nameH + rowGap
	self.rankLabel.Visible = showLabel
	if showLabel then
		HudParts.setTextSize(self.rankLabel, body)
		self.rankLabel.Position = UDim2.fromOffset(x, y)
		self.rankLabel.Size = UDim2.fromOffset(colW, labelH)
		y += labelH + rowGap
	end
	-- The XP bar, then "250 / 1,000 XP" beside it.
	self.rankXp.Text = state.xpWords
	HudParts.setTextSize(self.rankXp, body)
	local xpW = math.ceil(textWidth(state.xpWords, body)) + 4
	local barW = math.max(40, colW - xpW - 6)
	local barH = math.max(8, round(barRowH * 0.62))
	self.rankBar.Position = UDim2.fromOffset(x, y + round((barRowH - barH) / 2))
	self.rankBar.Size = UDim2.fromOffset(barW, barH)
	self.rankXp.Position = UDim2.fromOffset(x + barW + 6, y)
	self.rankXp.Size = UDim2.fromOffset(math.max(1, colW - barW - 6), barRowH)
	y += barRowH + rowGap
	self.nextRow.Position = UDim2.fromOffset(x, y)
	self.nextRow.Size = UDim2.fromOffset(colW, nextH)
	self:drawNext(nextLine, colW, nextH, body)
	y += nextH + rowGap
	self.help.Visible = showHelp
	if showHelp then
		HudParts.setTextSize(self.help, body)
		self.help.Position = UDim2.fromOffset(x, y)
		self.help.Size = UDim2.fromOffset(colW, helpH)
	end

	if self.barTween then
		self.barTween:Cancel()
		self.barTween = nil
	end
	local fillSize = UDim2.fromScale(state.fraction, 1)
	if live then
		local tween = TweenService:Create(
			self.rankFill,
			TweenInfo.new(Config.UI.Progress.CountUpSeconds, Enum.EasingStyle.Quad),
			{ Size = fillSize }
		)
		self.barTween = tween
		tween:Play()
	else
		self.rankFill.Size = fillSize
	end
	if self.rankFade then
		self.rankFade.Color = ColorSequence.new(WHITE, WHITE:Lerp(tierColor(rank.tier), R.CardTint))
	end
end

-- The next-division line, measured for a row `width` wide whose one line is `lineH` tall: an
-- arrow to the division's badge, "Next: Gold IV", and the money it pays (only if you have not
-- reached it before); at the top, "You are at the top!". The badge is left out first when the
-- line is too long; `fits` says whether the words then still fit on one line.
function Roadmap.measureNext(self: any, width: number, lineH: number, body: number): NextLine
	local state: State = self.state
	local target = state.rank.index + 1
	local top = target > Ranks.count()
	local words = P.TopRank
	local badgeImage = ""
	local amount = 0
	if not top then
		local tier, division = Ranks.at(target)
		words = P.NextDivision:format(divisionName(tier, division))
		badgeImage = RankBadge.image(tier, division)
		amount = Ranks.rewardFor(target).money
	end
	local pays = not top and target > state.peak and amount > 0
	local amountWords = Format.moneyDelta(amount)
	local gapX = math.max(3, round(lineH * 0.18))
	local arrow = if top then 0 else round(lineH * R.NextArrowShare)
	local badge = round(lineH * R.NextBadgeShare)
	local textW = math.ceil(textWidth(words, body)) + 4
	local chipH = math.min(lineH, body + 10)
	local cash = round(chipH * R.ChipIconShare)
	local cashX = round(chipH * 0.1)
	local amountX = cashX + cash + 2
	local amountW = math.ceil(textWidth(amountWords, body)) + 4
	local chipW = if pays then amountX + amountW + round(chipH * 0.35) else 0
	local chipRoom = if pays then gapX + chipW else 0
	local lead = if top then 0 else arrow + gapX
	local showBadge = not top and lead + badge + gapX + textW + chipRoom <= width
	local used = lead + (if showBadge then badge + gapX else 0) + textW + chipRoom
	return {
		top = top,
		words = words,
		badgeImage = badgeImage,
		pays = pays,
		amountWords = amountWords,
		gapX = gapX,
		arrow = arrow,
		badge = badge,
		showBadge = showBadge,
		textW = textW,
		chipH = chipH,
		chipW = chipW,
		cash = cash,
		cashX = cashX,
		amountX = amountX,
		amountW = amountW,
		fits = used <= width,
	}
end

-- Draw the measured next-division line into its row (`height` is one line, or two when its
-- words wrap); the arrow, badge and chip stay centred on it.
function Roadmap.drawNext(self: any, line: NextLine, width: number, height: number, body: number)
	local words = self.nextLine
	HudParts.setTextSize(words, body)
	words.Text = line.words
	self.nextArrow.Visible = not line.top
	self.nextBadge.Visible = line.showBadge
	self.chip.Visible = line.pays
	local x = 0
	if not line.top then
		self.nextArrow.Size = UDim2.fromOffset(line.arrow, line.arrow)
		self.nextArrow.Position = UDim2.fromOffset(x, round((height - line.arrow) / 2))
		x += line.arrow + line.gapX
	end
	if line.showBadge then
		self.nextBadge.Image = line.badgeImage
		self.nextBadge.Size = UDim2.fromOffset(line.badge, line.badge)
		self.nextBadge.Position = UDim2.fromOffset(x, round((height - line.badge) / 2))
		x += line.badge + line.gapX
	end
	local chipRoom = if line.pays then line.gapX + line.chipW else 0
	local textRoom = math.max(1, math.min(line.textW, width - x - chipRoom))
	words.Position = UDim2.fromOffset(x, 0)
	words.Size = UDim2.fromOffset(textRoom, height)
	x += textRoom + line.gapX
	if line.pays then
		local chipH = line.chipH
		self.chip.Size = UDim2.fromOffset(line.chipW, chipH)
		self.chip.Position = UDim2.fromOffset(x, round((height - chipH) / 2))
		self.chipCash.Size = UDim2.fromOffset(line.cash, line.cash)
		self.chipCash.Position = UDim2.new(0, line.cashX, 0.5, 0)
		self.chipAmount.Text = line.amountWords
		HudParts.setTextSize(self.chipAmount, body)
		self.chipAmount.Position = UDim2.fromOffset(line.amountX, 0)
		self.chipAmount.Size = UDim2.fromOffset(line.amountW, chipH)
	end
end

-- The chosen tier's rewards: its money, a case, its chat tag and a cue, in tiles as wide as
-- their words need (equal when they all fit).
function Roadmap.drawRewards(self: any)
	local geo: Geo? = self.geo
	local state: State? = self.state
	local tier: string? = self.selected
	if not geo or not state or not tier then
		return
	end
	local w, h = geo.rightW, geo.cardsH
	local body, heading = geo.body, geo.heading
	local p = math.max(4, round(h * R.CardPadShare))
	local titleH = heading + 4
	local title = self.rewardsTitle
	HudParts.setTextSize(title, heading)
	title.Text = P.RewardsFor:format(divisionName(tier, 1))
	title.Position = UDim2.fromOffset(p + 2, p)
	title.Size = UDim2.fromOffset(math.max(1, w - 2 * p - 4), titleH)
	local tilesY = p + titleH + math.max(2, round(p * 0.5))
	local tilesH = math.max(R.TouchMinPx, h - tilesY - p)
	local tileGap = spanPx(R.TileGapPx, geo.t)
	local inner = math.max(4, w - 2 * p - 3 * tileGap)
	local holder = self.tileHolder
	holder.Size = UDim2.fromOffset(inner + 3 * tileGap, tilesH)
	holder.Position =
		UDim2.fromOffset(p + round((inner + 3 * tileGap) / 2), tilesY + round(tilesH / 2))

	-- The words.
	local tiles: Tiles = self.tiles
	local name = Ranks.tierName(tier)
	local tierRow = TIER_REWARDS[tier]
	local money = Format.moneyDelta(if tierRow then tierRow.Money else 0)
	local plainTag = Strings.Ranks.ChatTag:format(string.upper(name))
	local cue = P.TierCue:format(name)
	tiles.money.value.Text = money
	tiles.case.value.Text = P.RewardCase
	tiles.chat.value.Text = ChatTags.tagFor(tier) or plainTag
	tiles.cue.value.Text = cue

	-- Each tile's least width: its words on one line, but the cue's name may take two.
	local labelSize = math.max(K.Text.Min, body - 2)
	local tp = math.max(3, round(tilesH * 0.06))
	local values = { money, P.RewardCase, plainTag, cue }
	local labels = { P.RewardMoney, P.RewardCount:format(1), P.RewardChatTag, "" }
	local needs: { number } = {}
	local total = 0
	for i, words in values do
		needs[i] = math.max(textWidth(words, body), textWidth(labels[i], labelSize)) + 2 * tp + 6
		total += needs[i]
	end
	if total > inner then
		local longest = 0
		for word in string.gmatch(cue, "%S+") do
			longest = math.max(longest, textWidth(word, body))
		end
		total -= needs[4]
		needs[4] = longest + 2 * tp + 6
		total += needs[4]
	end
	local biggest = math.max(needs[1], needs[2], needs[3], needs[4])
	local widths: { number } = {}
	for i, need in needs do
		widths[i] = if biggest * 4 <= inner
			then inner / 4
			elseif total <= inner then need + (inner - total) / 4
			else inner * need / total
	end

	local valueH, labelH = body + 4, labelSize + 2
	local iconSize = math.max(16, tilesH - 2 * tp - valueH - labelH)
	local check = round(tilesH * R.TileCheckShare)
	local soonH = math.max(K.Text.Min + 4, spanPx(R.SoonPx, geo.t))
	local soonText = math.max(K.Text.Min, round(soonH * 0.72))
	local corner = UDim.new(0, spanPx(R.TileCornerPx, geo.t))
	local x = 0
	for i, tile: Tile in self.tileOrder do
		local left, right = round(x), round(x + widths[i])
		x += widths[i] + tileGap
		local width = right - left
		tile.frame.Position = UDim2.fromOffset(left, 0)
		tile.frame.Size = UDim2.fromOffset(width, tilesH)
		tile.corner.CornerRadius = corner
		local icon = math.max(1, math.min(iconSize, width - 2 * tp))
		tile.icon.Size = UDim2.fromOffset(icon, icon)
		tile.icon.Position = UDim2.fromOffset(round(width / 2), tp + (iconSize - icon))
		local textY = tp + iconSize
		local textW = math.max(1, width - 2 * tp)
		HudParts.setTextSize(tile.value, body)
		tile.value.Position = UDim2.fromOffset(tp, textY)
		local label = tile.label
		if label then
			tile.value.Size = UDim2.fromOffset(textW, valueH)
			HudParts.setTextSize(label, labelSize)
			label.Position = UDim2.fromOffset(tp, textY + valueH - 1)
			label.Size = UDim2.fromOffset(textW, labelH)
		else
			tile.value.Size = UDim2.fromOffset(textW, valueH + labelH)
		end
		tile.check.Size = UDim2.fromOffset(check, check)
		tile.check.Position = UDim2.fromOffset(width - 2, 2)
		local soon, soonWords = tile.soon, tile.soonWords
		if soon and soonWords then
			HudParts.setTextSize(soonWords, soonText)
			soon.Size = UDim2.fromOffset(round(textWidth(P.Soon, soonText) + soonH), soonH)
			soon.Position = UDim2.fromOffset(width - 3, -round(soonH * 0.35))
		end
	end
	-- A check on the rewards given now, for a tier you have reached.
	local earned = (Ranks.tierIndex(tier) or 0) <= state.order
	tiles.money.check.Visible = earned
	tiles.chat.check.Visible = earned
end

--------------------------------------------------------------------------------------------
-- State (from the player's rank attributes)
--------------------------------------------------------------------------------------------

-- Breathe the next tier's badge (only one at a time, only while open).
function Roadmap.setPulse(self: any, cell: Cell?)
	if self.pulseCell == cell then
		return
	end
	if self.pulse then
		self.pulse.stop()
		self.pulse = nil
	end
	self.pulseCell = cell
	if cell then
		self.pulse = UIAnim.pulse(cell.art)
	end
end

-- A tier's gold outline: solid with a pale fill when chosen, lighter while hovered or focused.
function Roadmap.paintRing(self: any, cell: Cell)
	local chosen = self.selected == cell.tier
	cell.ring.Visible = chosen or cell.lit
	cell.ring.BackgroundTransparency = if chosen then R.RingFillTransparency else 1
	cell.ringEdge.Transparency = if chosen then 0 else R.FocusRingTransparency
end

-- A tier under the mouse or a gamepad: the outline, a small pop and the hover sound.
function Roadmap.lightCell(self: any, cell: Cell, on: boolean)
	if cell.lit == on then
		return
	end
	cell.lit = on
	self:paintRing(cell)
	if on then
		UISound.play("BadgeHover")
	end
	settleCell(cell, nil, QUICK * 2)
end

-- Every tier's state: reached, yours, the next, locked past it (grey and see-through), and its
-- dots, gold for each division reached.
function Roadmap.paintRow(self: any)
	local state: State = self.state
	local current = state.order
	local lockedTint = color(R.LockedTint)
	local empty = color(R.DotEmptyColor)
	for order, cell: Cell in self.cells do
		local mine = order == current
		local locked = order > current + 1
		cell.image.Visible = not mine
		cell.image.ImageColor3 = if locked then lockedTint else WHITE
		cell.image.ImageTransparency = if locked then R.LockedTransparency else 0
		local fade = if locked then R.LockedTextTransparency else 0
		HudParts.setTextTransparency(cell.name, fade)
		local filled = if order < current
			then #cell.dots
			elseif mine then math.max(1, state.rank.division)
			else 0
		for i, dotFrame in cell.dots do
			dotFrame.BackgroundColor3 = if i <= filled then GOLD else empty
			dotFrame.BackgroundTransparency = fade
			local edge = dotFrame:FindFirstChildOfClass("UIStroke")
			if edge then
				edge.Transparency = fade
			end
		end
		self:paintRing(cell)
	end
	self:setPulse(if self.opened then self.cells[current + 1] else nil)
end

--- Draw the player's rank on the map: the row, your badge, the tags, your rank's card and the
--- chosen tier's rewards. `live` animates a change seen while the map is open (the badges pop,
--- the bar slides, the row glides to your tier). A new tier chooses the next one again.
function Roadmap.draw(self: any, live: boolean)
	if not self.geo then
		return
	end
	local state = readState(self.player)
	local previous: State? = self.state
	local moved = previous == nil or previous.rank.index ~= state.rank.index
	local tierMoved = previous == nil or previous.order ~= state.order
	self.state = state
	if tierMoved or self.selected == nil then
		self.selected = defaultTier(state)
	end
	self:layoutRow()
	self:paintRow()
	self.rowBadge:set(state.rank.tier, state.rank.division, live and moved)
	self:drawRankCard(live, moved)
	self:drawRewards()
	local back: Cell = self.focusCell or self:cellFor(self.selected)
	self.closeButton.NextSelectionDown = back.button
	self:updateArrows()
	if live and tierMoved then
		self:scrollToCell(self.cells[math.max(1, state.order)])
	end
end

-- Choose a tier: the gold outline moves and the rewards card shows it (the tiles pop).
function Roadmap.choose(self: any, tier: string, nudge: boolean)
	if self.selected == tier then
		return
	end
	self.selected = tier
	for _, cell: Cell in self.cells do
		self:paintRing(cell)
	end
	self:drawRewards()
	if nudge then
		if self.nudgeTween then
			self.nudgeTween:Cancel()
		end
		self.nudge.Scale = R.NudgeScale
		local tween = TweenService:Create(
			self.nudge,
			TweenInfo.new(R.NudgeSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }
		)
		self.nudgeTween = tween
		tween:Play()
	end
end

function Roadmap.cellFor(self: any, tier: string?): Cell
	return self.cells[math.max(1, if tier then Ranks.tierIndex(tier) or 1 else 1)]
end

-- Redraw once after a burst of attribute changes (the server sets several at once).
function Roadmap.queueRefresh(self: any)
	if self.refreshQueued then
		return
	end
	self.refreshQueued = true
	task.defer(function()
		self.refreshQueued = false
		if self.opened and self.alive then
			self:draw(true)
		end
	end)
end

--------------------------------------------------------------------------------------------
-- Scrolling and input
--------------------------------------------------------------------------------------------

function Roadmap.clampCanvas(self: any, x: number): number
	local row: Row? = self.row
	if not row then
		return 0
	end
	return math.clamp(x, 0, math.max(0, row.canvasW - row.viewW))
end

-- Glide the row until a tier is in the middle (a gamepad moving along it).
function Roadmap.scrollToCell(self: any, cell: Cell)
	local row: Row? = self.row
	if row then
		self.scrollTarget = self:clampCanvas(cell.x + cell.w / 2 - row.viewW / 2)
		self.holdUntil = 0
	end
end

-- Glide the row just enough to show a tier whole (a tap on one at the edge).
function Roadmap.revealCell(self: any, cell: Cell)
	local row: Row? = self.row
	if not row then
		return
	end
	local left = self.scrollTarget or self.scroll.CanvasPosition.X
	if cell.x < left then
		self.scrollTarget = self:clampCanvas(cell.x)
	elseif cell.x + cell.w > left + row.viewW then
		self.scrollTarget = self:clampCanvas(cell.x + cell.w - row.viewW)
	end
end

-- One tier along (the arrows): the row's left edge glides to the next tier's edge that way.
function Roadmap.stepRow(self: any, dir: number)
	if not self.row then
		return
	end
	local left = self.scrollTarget or self.scroll.CanvasPosition.X
	local target = if dir > 0 then math.huge else 0
	for _, cell: Cell in self.cells do
		if dir > 0 and cell.x > left + 1 then
			target = math.min(target, cell.x)
		elseif dir < 0 and cell.x < left - 1 then
			target = math.max(target, cell.x)
		end
	end
	self.scrollTarget = self:clampCanvas(target)
	self.holdUntil = 0
end

-- Put your tier in the middle now, and hold it there through the opening pop (the panel's
-- scale is still settling).
function Roadmap.centre(self: any, hold: boolean)
	local row: Row? = self.row
	local state: State? = self.state
	if not row or not state then
		return
	end
	local cell: Cell = self.cells[math.max(1, state.order)]
	local x = self:clampCanvas(cell.x + cell.w / 2 - row.viewW / 2)
	self.scroll.CanvasPosition = Vector2.new(x, 0)
	self.scrollTarget = x
	self.holdUntil = if hold then os.clock() + K.Motion.PopSeconds + 0.1 else 0
	self:updateArrows()
end

-- Fade an arrow at the row's end (it stays pressable and selectable; it just does nothing).
function Roadmap.fadeArrow(self: any, button: TextButton, chevron: ImageLabel, faded: boolean)
	if self.arrowFaded[button] == faded then
		return
	end
	self.arrowFaded[button] = faded
	HudParts.setEnabled(button, true, faded)
	chevron.ImageTransparency = if faded then K.DisabledTransparency else 0
end

function Roadmap.updateArrows(self: any)
	local row: Row? = self.row
	if not row then
		return
	end
	local x = self.scroll.CanvasPosition.X
	local most = math.max(0, row.canvasW - row.viewW)
	self:fadeArrow(self.backArrow, self.backChevron, x <= 0.5)
	self:fadeArrow(self.forwardArrow, self.forwardChevron, x >= most - 0.5)
end

function Roadmap.overRow(self: any, position: Vector3): boolean
	local corner: Vector2 = self.scroll.AbsolutePosition
	local size: Vector2 = self.scroll.AbsoluteSize
	return position.X >= corner.X
		and position.X <= corner.X + size.X
		and position.Y >= corner.Y
		and position.Y <= corner.Y + size.Y
end

function Roadmap.focused(self: any): boolean
	local selected = GuiService.SelectedObject
	return selected ~= nil and selected:IsDescendantOf(self.panel)
end

-- Put the gamepad on the chosen tier.
function Roadmap.focus(self: any)
	GuiService.SelectedObject = self:cellFor(self.selected).button
end

function Roadmap.onInputBegan(self: any, input: InputObject)
	local code = input.KeyCode
	if code == Enum.KeyCode.ButtonB or code == Enum.KeyCode.Escape then
		self:close()
		return
	elseif code == Enum.KeyCode.ButtonA then
		self.dragMoved = false -- an old mouse drag must not swallow a gamepad press
	end
	local kind = input.UserInputType
	if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
		self.dragMoved = false
		if self:overRow(input.Position) then
			self.scrollTarget = nil -- a finger or the mouse takes over from a glide
			if kind == Enum.UserInputType.MouseButton1 then
				self.drag = { x = input.Position.X, canvas = self.scroll.CanvasPosition.X }
			end
		end
	end
end

function Roadmap.onInputChanged(self: any, input: InputObject)
	local kind = input.UserInputType
	if kind == Enum.UserInputType.MouseWheel then
		-- The wheel moves the row sideways. Driving it to a target every frame also overrides
		-- any scrolling Roblox does with the wheel by itself.
		if self:overRow(input.Position) then
			local from = self.scrollTarget or self.scroll.CanvasPosition.X
			self.scrollTarget = self:clampCanvas(from - input.Position.Z * R.WheelStepPx)
			self.holdUntil = 0
		end
	elseif kind == Enum.UserInputType.MouseMovement then
		local drag = self.drag
		if drag then
			local dx = input.Position.X - drag.x
			if not self.dragMoved and math.abs(dx) >= R.DragThresholdPx then
				self.dragMoved = true
			end
			if self.dragMoved then
				self.scrollTarget = nil
				self.scroll.CanvasPosition = Vector2.new(self:clampCanvas(drag.canvas - dx), 0)
			end
		end
	end
end

-- Every frame while open: the row's glide.
function Roadmap.step(self: any, dt: number)
	local target = self.scrollTarget
	if not target then
		return
	end
	local scroll = self.scroll
	local x = scroll.CanvasPosition.X
	local nextX = target
	if os.clock() >= self.holdUntil then
		nextX = x + (target - x) * (1 - math.exp(-dt / R.ScrollEaseSeconds))
		if math.abs(target - nextX) < 0.5 then
			nextX = target
			self.scrollTarget = nil
		end
	end
	scroll.CanvasPosition = Vector2.new(nextX, 0)
end

function Roadmap.startLoops(self: any)
	self.rowBadge:setShining(true)
	self.rankBadge:setShining(true)
	self.spinner = UIAnim.spin(self.glow, R.GlowDegreesPerSecond)
	self.stepper = RunService.RenderStepped:Connect(function(dt)
		self:step(dt)
	end)
	local state: State? = self.state
	self:setPulse(if state then self.cells[state.order + 1] else nil)
end

function Roadmap.stopLoops(self: any)
	if self.rowBadge then
		self.rowBadge:setShining(false)
		self.rankBadge:setShining(false)
	end
	if self.spinner then
		self.spinner.stop()
		self.spinner = nil
	end
	if self.stepper then
		self.stepper:Disconnect()
		self.stepper = nil
	end
	if self.barTween then
		self.barTween:Cancel()
		self.barTween = nil
	end
	if self.nudgeTween then
		self.nudgeTween:Cancel()
		self.nudgeTween = nil
		self.nudge.Scale = 1
	end
	self:setPulse(nil)
end

function Roadmap.listen(self: any)
	local list = self.openConnections
	table.insert(
		list,
		UserInputService.InputBegan:Connect(function(input)
			self:onInputBegan(input)
		end)
	)
	table.insert(
		list,
		UserInputService.InputChanged:Connect(function(input)
			self:onInputChanged(input)
		end)
	)
	table.insert(
		list,
		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				self.drag = nil
			end
		end)
	)
	-- A gamepad picked up while the map is open lands on the chosen tier.
	table.insert(
		list,
		UserInputService.LastInputTypeChanged:Connect(function(kind)
			if isGamepad(kind) and not self:focused() then
				self:focus()
			end
		end)
	)
	local player = self.player
	if player then
		for _, name in WATCHED do
			table.insert(
				list,
				player:GetAttributeChangedSignal(name):Connect(function()
					self:queueRefresh()
				end)
			)
		end
	end
	-- B closes the map before anything else hears it (the table's own B is Leave).
	ContextActionService:BindActionAtPriority(
		CLOSE_ACTION,
		function(_name: string, state: Enum.UserInputState, _input: InputObject)
			if state == Enum.UserInputState.Begin then
				self:close()
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.ContextActionPriority.High.Value + 10,
		Enum.KeyCode.ButtonB
	)
	self.bound = true
end

function Roadmap.unlisten(self: any)
	for _, connection in self.openConnections do
		connection:Disconnect()
	end
	table.clear(self.openConnections)
	if self.bound then
		self.bound = false
		ContextActionService:UnbindAction(CLOSE_ACTION)
	end
end

-- Give a gamepad back what it had before the map opened.
function Roadmap.releaseSelection(self: any)
	local selected = GuiService.SelectedObject
	if selected and self.root and selected:IsDescendantOf(self.root) then
		local previous = self.previousSelection
		GuiService.SelectedObject = if previous and previous:IsDescendantOf(game)
			then previous
			else nil
	end
	self.previousSelection = nil
end

--------------------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------------------

--- Pop the map in, centred on your tier, the rewards card on the next. A gamepad lands on
--- the chosen tier.
function Roadmap.open(self: any)
	if self.opened or not self.alive then
		return
	end
	if not self.built then
		self:build()
	end
	self.opened = true
	self.gui.Enabled = true
	self.state = nil
	self.selected = nil
	self.focusCell = nil
	if self:layout() then
		self:draw(false)
		self:centre(true)
	end
	if self.dimTween then
		self.dimTween:Cancel()
	end
	self.dimTween = TweenService:Create(
		self.dim,
		TweenInfo.new(R.DimSeconds),
		{ BackgroundTransparency = R.DimTransparency }
	)
	self.dimTween:Play()
	UIAnim.popIn(self.panel)
	self:startLoops()
	self:listen()
	self.previousSelection = GuiService.SelectedObject
	if isGamepad(UserInputService:GetLastInputType()) then
		self:focus()
	end
end

--- Pop the map out (the X, the backdrop, gamepad B or Escape all come here).
function Roadmap.close(self: any)
	if not self.opened then
		return
	end
	self.opened = false
	self:stopLoops()
	self:unlisten()
	self.drag = nil
	self.scrollTarget = nil
	for _, cell: Cell in self.cells do
		if cell.lit then
			cell.lit = false
			self:paintRing(cell)
			settleCell(cell, nil, QUICK)
		end
	end
	self:releaseSelection()
	if self.dimTween then
		self.dimTween:Cancel()
	end
	self.dimTween =
		TweenService:Create(self.dim, TweenInfo.new(R.DimSeconds), { BackgroundTransparency = 1 })
	self.dimTween:Play()
	UIAnim.popOut(self.panel, function()
		if not self.opened and self.alive then
			self.gui.Enabled = false
		end
	end)
end

function Roadmap.isOpen(self: any): boolean
	return self.opened
end

function Roadmap.destroy(self: any)
	if not self.alive then
		return
	end
	if self.opened then
		self.opened = false
		self:stopLoops()
		self:unlisten()
		self:releaseSelection()
	end
	self.alive = false
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	if self.built then
		self.rowBadge:destroy()
		self.rankBadge:destroy()
		self.gui:Destroy()
		self.probe:Destroy()
	end
end

return Roadmap
