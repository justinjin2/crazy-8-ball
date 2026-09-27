--!strict
-- Roadmap: the rank roadmap (docs/prompts/RANKS_MONEY_PROMPT.md section 12, reference
-- 03-ranked-roadmap). Pressing the rank HUD's badge opens it: a big white kit panel over a dim
-- backdrop with the trophy, "Ranked", a short subtitle and a red close X; a card with your
-- rank and its XP bar and a card with the next money reward; the road; the ten tiers as jump
-- buttons; and one line of rules.
--
-- The road scrolls sideways through every division (Ranks.list(), 46 stops), from a start
-- stop where Unranked players stand to Reyes. Tier changes are the landmarks: each tier's
-- division I is a big gate on a band of the tier's colour, with the tier's name, and
-- divisions II to V are smaller stops after it, inside a light zone of that colour. Between
-- two stops a chip on the road shows the money paid the first time you reach the next one; a
-- tier's first division pays more, so its chip is bigger and gold and shines now and then.
--
-- States come from the local player's attributes (RankXp, RatedMatches, PeakDivision): the
-- stops you have reached are in full colour with a check; yours glows over turning rays, with
-- your picture and YOU above it and a tiny XP bar under it; the next one breathes under a
-- Next tag; the rest are greyed and see-through. Only your badge shines. The road is gold up
-- to where you are, and rewards already paid are faded with a check.
--
-- Swipe on a touch screen; drag or turn the wheel with a mouse; on a gamepad the stick or
-- D-pad moves between stops (the road glides to keep the selected one in the middle), down
-- goes to the tier strip, up to the close X, and B closes. Every size comes from the screen:
-- on a phone the panel takes the whole screen, its title in Roblox's top bar row right of
-- Roblox's buttons, so the road keeps its height; on a computer it is capped. Numbers are in
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
local TIERS: { string } = Config.Ranks.Tiers
local TOP_TIER = TIERS[#TIERS]
local TIER_COLORS: { [string]: { number } } = Config.Ranks.Colors :: any
local QUICK = Config.Multiplayer.Style.QuickMotion
local CASH = "CashSingle" -- the one bundle, as on the flying "+$10" chips (Config.UI.Kit.Icons)
local CLOSE_ACTION = "8ballRoadmapClose"
-- The save's rank as the server replicates it (PlayerData); any change redraws the map.
local WATCHED = { "RankXp", "RatedMatches", "PeakDivision", "RankIndex" }

type Stop = {
	index: number, -- 0 is the start (Unranked)
	tier: string,
	division: number,
	gate: boolean, -- a tier's division I
	button: TextButton,
	hover: UIScale, -- hover, selection and press
	art: Frame, -- the badge's holder (breathes when it is the next stop)
	image: ImageLabel, -- the still badge (your stop shows the shining RankBadge instead)
	check: ImageLabel,
	label: TextLabel, -- the tier's name on a gate, the numeral on a small stop
	ring: Frame, -- gold, while hovered or selected
	x: number, -- centre, in the road's canvas pixels
	size: number,
	lit: boolean,
	tween: Tween?,
}

type Chip = {
	index: number, -- the stop it leads into
	amount: number,
	promo: boolean, -- a tier's first division
	words: string,
	pill: Frame,
	edge: UIStroke?,
	icon: ImageLabel,
	paid: ImageLabel,
	text: TextLabel,
	x: number,
	claimed: boolean,
}

type Zone = {
	tier: string,
	first: number, -- its gate's stop
	last: number,
	frame: Frame,
	corner: UICorner,
	banner: Frame,
	bannerCorner: UICorner,
}

type TierButton = { tier: string, button: TextButton, badge: ImageLabel, name: TextLabel }

type Geo = {
	g: number, -- a gate's badge
	s: number, -- a small stop's badge
	cy: number, -- the badges' centre line
	h: number, -- the road's height
	viewW: number, -- the road's visible width
	canvasW: number,
	thick: number, -- the road band
	labelGate: number,
	labelSmall: number,
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
	circle(track)
	stroke(track, INK, 2)
	local fill = HudParts.frame(track, "Fill")
	fill.BackgroundTransparency = 0
	fill.BackgroundColor3 = WHITE
	fill.Size = UDim2.fromScale(0, 1)
	circle(fill)
	local shade = Instance.new("UIGradient")
	shade.Rotation = 90
	shade.Color = ColorSequence.new(color(R.BarTopColor), tone("Gold"))
	shade.Parent = fill
	return track, fill
end

-- A small round tag with words (YOU, Next), hung by its bottom middle.
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

local function signed(n: number): string
	return if n > 0 then "+" .. Format.xp(n) else Format.xp(n)
end

-- One group of tiers in words: "Expert", "Platinum and Diamond", "Bronze to Gold" (three or
-- more in a row), or a list when they are not in a row. Nil for an empty group.
local function tierWords(tiers: { string }): string?
	local n = #tiers
	if n == 0 then
		return nil
	end
	local names: { string } = {}
	local inRow = true
	for i, tier in tiers do
		names[i] = Ranks.tierName(tier)
		if i > 1 and (Ranks.tierIndex(tier) or 0) ~= (Ranks.tierIndex(tiers[i - 1]) or 0) + 1 then
			inRow = false
		end
	end
	if n == 1 then
		return names[1]
	elseif n == 2 then
		return P.TierPair:format(names[1], names[2])
	elseif inRow then
		return P.TierRange:format(names[1], names[n])
	end
	local text = names[1]
	for i = 2, n do
		text = P.TierList:format(text, names[i])
	end
	return text
end

-- The one line of rules, from Config.Ranks through Ranks.rulesLine: "Win +250 XP. Bronze to
-- Gold: losing still gives +50. Platinum and Diamond: no XP lost. Expert and up: losing costs
-- 150." Stored whole in Strings; if Config leaves a group of tiers empty, that sentence goes.
local function rulesText(): string
	local line = Ranks.rulesLine()
	local win = signed(line.win)
	local low = tierWords(line.lossTiersLow)
	local free = tierWords(line.freeTiers)
	local lose = line.loseTiers
	local cost = Format.xp(math.abs(line.highLoss))
	-- "Expert and up" when the tiers that lose XP run in a row up to the top.
	local upFrom: string? = nil
	if #lose > 0 and lose[#lose] == TOP_TIER then
		if (Ranks.tierIndex(lose[1]) or 0) + #lose - 1 == #TIERS then
			upFrom = Ranks.tierName(lose[1])
		end
	end
	if low and free and upFrom then
		return P.Rules:format(win, low, signed(line.lowLoss), free, upFrom, cost)
	end
	local parts = { P.RulesWin:format(win) }
	if low then
		table.insert(parts, P.RulesLow:format(low, signed(line.lowLoss)))
	end
	if free then
		table.insert(parts, P.RulesFree:format(free))
	end
	local high = tierWords(lose)
	if upFrom then
		table.insert(parts, P.RulesHighUp:format(upFrom, cost))
	elseif high then
		table.insert(parts, P.RulesHigh:format(high, cost))
	end
	return table.concat(parts, " ")
end

-- Tween a stop's scale back to where it rests (up while lit), from `from` if given.
local function settleStop(stop: Stop, from: number?, seconds: number)
	if stop.tween then
		stop.tween:Cancel()
	end
	if from then
		stop.hover.Scale = from
	end
	local tween = TweenService:Create(
		stop.hover,
		TweenInfo.new(seconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = if stop.lit then R.HoverScale else 1 }
	)
	stop.tween = tween
	tween:Play()
end

-- A stop under the mouse or a gamepad: the gold ring, a small pop and the hover sound.
local function lightStop(stop: Stop, on: boolean)
	if stop.lit == on then
		return
	end
	stop.lit = on
	stop.ring.Visible = on
	if on then
		UISound.play("BadgeHover")
	end
	settleStop(stop, nil, QUICK * 2)
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
	self.geo = nil
	self.current = -1 -- the stop that holds the shining badge
	self.lastStop = nil -- the last stop a gamepad was on (the close X leads back to it)
	self.scrollTarget = nil -- a canvas X the road is gliding to
	self.holdUntil = 0 -- the road is held on its target until then (the opening pop)
	self.shineClock = 0
	self.drag = nil -- a mouse drag of the road
	self.dragMoved = false -- the last press dragged (so its release is not a press)
	self.refreshQueued = false
	self.pulse = nil
	self.pulseStop = nil
	self.spinner = nil
	self.stepper = nil
	self.dimTween = nil
	self.barTween = nil
	self.previousSelection = nil
	return self :: Roadmap
end

-- One stop on the road: a selectable button holding the badge, its check, its name or
-- numeral and the gold ring shown while it is hovered or selected.
local function makeStop(self: any, index: number, tier: string, division: number): Stop
	local gate = division == 1
	local button = Instance.new("TextButton")
	button.Name = "Stop" .. index
	button.Text = ""
	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Selectable = true
	button.SelectionImageObject = self.noBox
	button.ZIndex = if gate then 2 else 1
	local hover = Instance.new("UIScale")
	hover.Name = "Hover"
	hover.Parent = button
	local art = HudParts.frame(button, "Art")
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.Position = UDim2.fromScale(0.5, 0.5)
	art.Size = UDim2.fromScale(1, 1)
	art.ZIndex = 1
	local image = Instance.new("ImageLabel")
	image.Name = "Badge"
	image.BackgroundTransparency = 1
	image.ScaleType = Enum.ScaleType.Fit
	image.Image = RankBadge.image(tier, division)
	image.Size = UDim2.fromScale(1, 1)
	image.Parent = art
	local ring = HudParts.frame(button, "Ring")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(R.RingShare, R.RingShare)
	ring.ZIndex = 3
	ring.Visible = false
	circle(ring)
	stroke(ring, tone("Gold"), R.RingPx)
	local check = HudParts.icon(button, "Check", "Check")
	check.AnchorPoint = Vector2.new(0.5, 0.5)
	check.Position = UDim2.fromScale(0.8, 0.74)
	check.Size = UDim2.fromScale(R.CheckShare, R.CheckShare)
	check.ZIndex = 4
	check.Visible = false
	local words = if index == 0
		then Strings.Ranks.Unranked
		elseif gate then Ranks.tierName(tier)
		else Strings.Ranks.Numerals[division] or ""
	local label = HudParts.text(button, "Name", K.Text.Body, words)
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.TextWrapped = false
	label.ZIndex = 4
	button.Parent = self.stopLayer
	local stop: Stop = {
		index = index,
		tier = tier,
		division = division,
		gate = gate,
		button = button,
		hover = hover,
		art = art,
		image = image,
		check = check,
		label = label,
		ring = ring,
		x = 0,
		size = 0,
		lit = false,
		tween = nil,
	}
	button.MouseEnter:Connect(function()
		if UserInputService:GetLastInputType() ~= Enum.UserInputType.Touch then
			lightStop(stop, true)
		end
	end)
	button.MouseLeave:Connect(function()
		lightStop(stop, false)
	end)
	button.SelectionGained:Connect(function()
		self.lastStop = stop
		self.closeButton.NextSelectionDown = button
		lightStop(stop, true)
		self:scrollTo(stop.x)
	end)
	button.SelectionLost:Connect(function()
		lightStop(stop, false)
	end)
	button.Activated:Connect(function()
		if not self.dragMoved then
			UISound.play("Click")
			self:scrollTo(stop.x)
			settleStop(stop, R.PressScale, R.PressSeconds)
		end
	end)
	return stop
end

-- A reward chip on the road: the cash bundle and the amount, and a check once it is paid.
local function makeChip(self: any, index: number, amount: number, promo: boolean): Chip
	local pill =
		HudParts.pill(self.chipLayer, "Chip" .. index, if promo then tone("Gold") else WHITE)
	pill.AnchorPoint = Vector2.new(0.5, 0.5)
	pill.Visible = amount > 0
	local icon = HudParts.icon(pill, CASH, "Cash")
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.ZIndex = 2
	local paid = HudParts.icon(pill, "Check", "Paid")
	paid.AnchorPoint = Vector2.new(0.5, 0.5)
	paid.ZIndex = 3
	paid.Visible = false
	local words = Format.money(amount)
	local text = HudParts.text(pill, "Amount", K.Text.Body, words)
	text.TextWrapped = false
	text.AutoLocalize = false -- a number
	text.ZIndex = 2
	local edge = pill:FindFirstChildOfClass("UIStroke")
	return {
		index = index,
		amount = amount,
		promo = promo,
		words = words,
		pill = pill,
		edge = edge,
		icon = icon,
		paid = paid,
		text = text,
		x = 0,
		claimed = false,
	}
end

-- A tier's light zone of its colour behind its five stops, and the stronger band behind its
-- gate, fading down from the top.
local function makeZone(self: any, tier: string, first: number, last: number): Zone
	local tint = tierColor(tier)
	local zone = HudParts.frame(self.zoneLayer, tier)
	zone.BackgroundTransparency = R.ZoneTransparency
	zone.BackgroundColor3 = tint
	local corner = Instance.new("UICorner")
	corner.Parent = zone
	stroke(zone, tint, 2).Transparency = 0.4
	local banner = HudParts.frame(self.zoneLayer, tier .. "Gate")
	banner.ZIndex = 2
	banner.BackgroundTransparency = R.BannerTransparency
	banner.BackgroundColor3 = tint
	local bannerCorner = Instance.new("UICorner")
	bannerCorner.Parent = banner
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Transparency = NumberSequence.new(0, 0.6)
	fade.Parent = banner
	return {
		tier = tier,
		first = first,
		last = last,
		frame = zone,
		corner = corner,
		banner = banner,
		bannerCorner = bannerCorner,
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

function Roadmap.buildCards(self: any, card: Frame)
	-- Your rank: the badge, its name, the XP bar and how to earn more.
	local current = HudParts.card(card, "CurrentCard")
	self.currentCard = current
	local fill = current:FindFirstChild("Fill")
	self.currentFade = if fill then fill:FindFirstChildOfClass("UIGradient") else nil
	local holder = HudParts.frame(current, "BadgeHolder")
	holder.ZIndex = 2
	self.currentBadgeHolder = holder
	self.currentBadge = RankBadge.new(holder, {
		size = 64,
		interactive = false,
		shine = false,
		name = "Badge",
	})
	local name = HudParts.text(current, "RankName", K.Text.Heading, "")
	name.TextWrapped = false
	name.TextXAlignment = Enum.TextXAlignment.Left
	self.currentName = name
	self.currentBar, self.currentFill = makeBar(current, "XpBar")
	local xp = HudParts.note(current, "Xp", K.Text.Body, "")
	xp.TextWrapped = false
	xp.TextXAlignment = Enum.TextXAlignment.Left
	self.currentXp = xp
	local earn = HudParts.note(current, "EarnXp", K.Text.Body, P.EarnXp)
	earn.TextWrapped = false
	earn.TextXAlignment = Enum.TextXAlignment.Left
	self.earn = earn
	-- The next money reward: its rank's badge, "Next: Gold IV, +$200" and the cash.
	local nextCard = HudParts.card(card, "NextCard")
	self.nextCard = nextCard
	local badge = Instance.new("ImageLabel")
	badge.Name = "NextBadge"
	badge.BackgroundTransparency = 1
	badge.ScaleType = Enum.ScaleType.Fit
	badge.Parent = nextCard
	self.nextBadge = badge
	local words = HudParts.text(nextCard, "NextReward", K.Text.Heading, "")
	words.TextXAlignment = Enum.TextXAlignment.Left
	self.nextText = words
	self.nextCash = HudParts.icon(nextCard, CASH, "Cash")
end

function Roadmap.buildRoad(self: any, card: Frame)
	local window = HudParts.frame(card, "RoadWindow")
	window.BackgroundTransparency = 0
	window.BackgroundColor3 = color(R.TrackColor)
	local corner = Instance.new("UICorner")
	corner.Parent = window
	self.windowCorner = corner
	stroke(window, INK, 2.5)
	self.window = window
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Road"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Selectable = false
	scroll.ScrollingDirection = Enum.ScrollingDirection.X
	scroll.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
	scroll.ScrollBarThickness = R.ScrollBarPx
	scroll.ScrollBarImageColor3 = INK
	scroll.ScrollBarImageTransparency = 0.5
	scroll.HorizontalScrollBarInset = Enum.ScrollBarInset.None
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.Parent = window
	self.scroll = scroll
	local layers = {}
	local function layer(name: string, z: number): Frame
		local object = HudParts.frame(scroll, name)
		object.ZIndex = z
		table.insert(layers, object)
		return object
	end
	self.zoneLayer = layer("Zones", 1)
	self.roadLayer = layer("RoadBand", 2)
	self.chipLayer = layer("Chips", 3)
	self.stopLayer = layer("Stops", 4)
	self.tagLayer = layer("Tags", 5)
	self.layers = layers

	-- The road: grey still to travel, gold where you have been.
	local band = HudParts.frame(self.roadLayer, "Band")
	band.BackgroundTransparency = 0
	band.BackgroundColor3 = color(R.RoadColor)
	circle(band)
	stroke(band, INK, 2.5)
	self.band = band
	local travelled = HudParts.frame(band, "Travelled")
	travelled.BackgroundTransparency = 0
	travelled.BackgroundColor3 = WHITE
	circle(travelled)
	local shade = Instance.new("UIGradient")
	shade.Rotation = 90
	shade.Color = ColorSequence.new(color(R.BarTopColor), tone("Gold"))
	shade.Parent = travelled
	self.travelled = travelled
	-- Gold rays turning behind your badge (over the road, under the chips and stops).
	local glow = Instance.new("ImageLabel")
	glow.Name = "Glow"
	glow.BackgroundTransparency = 1
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Image = K.Art.Rays
	glow.ImageColor3 = tone("Gold")
	glow.ImageTransparency = R.GlowTransparency
	glow.ZIndex = 2
	glow.Visible = false
	glow.Parent = self.roadLayer
	self.glow = glow

	-- Every stop, the chip leading into it, and each tier's zone.
	self.stops = {} :: { [number]: Stop }
	self.chips = {} :: { Chip }
	self.stops[0] = makeStop(self, 0, "Unranked", 0)
	local spans: { [string]: { number } } = {}
	for _, division in Ranks.list() do
		self.stops[division.index] =
			makeStop(self, division.index, division.tier, division.division)
		self.chips[division.index] =
			makeChip(self, division.index, division.reward, division.division == 1)
		local span = spans[division.tier]
		if span then
			span[2] = division.index
		else
			spans[division.tier] = { division.index, division.index }
		end
	end
	self.zones = {} :: { Zone }
	for _, tier in TIERS do
		local span = spans[tier]
		if span then
			table.insert(self.zones, makeZone(self, tier, span[1], span[2]))
		end
	end

	-- You: your picture over YOU, above your stop.
	local you = HudParts.frame(self.tagLayer, "You")
	you.AnchorPoint = Vector2.new(0.5, 1)
	self.you = you
	local head = HudParts.frame(you, "Head")
	head.AnchorPoint = Vector2.new(0.5, 0)
	head.Position = UDim2.fromScale(0.5, 0)
	head.BackgroundTransparency = 0
	head.BackgroundColor3 = WHITE
	circle(head)
	stroke(head, INK, 2.5)
	self.head = head
	local picture = Instance.new("ImageLabel")
	picture.Name = "Picture"
	picture.BackgroundTransparency = 1
	picture.ScaleType = Enum.ScaleType.Fit
	picture.Image = K.Icons.Person
	picture.Size = UDim2.fromScale(1, 1)
	circle(picture)
	picture.Parent = head
	self.picture = picture
	self.youTag, self.youWords = makeTag(you, "Tag", tone("Blue"), P.You)
	self.youTag.Position = UDim2.fromScale(0.5, 1)
	self.youTag.ZIndex = 2
	self.nextTag, self.nextWords = makeTag(self.tagLayer, "NextTag", color(R.NextTagColor), P.Next)
	self.miniTrack, self.miniFill = makeBar(self.tagLayer, "MiniXp")
	self.miniTrack.AnchorPoint = Vector2.new(0.5, 0)
	-- The shining badge sits in your stop (refresh moves it).
	self.roadBadge = RankBadge.new(self.stopLayer, {
		size = 64,
		interactive = false,
		shine = false,
		name = "YourBadge",
	})
end

function Roadmap.buildStrip(self: any, card: Frame)
	local strip = HudParts.frame(card, "Tiers")
	self.strip = strip
	self.tierButtons = {} :: { TierButton }
	for _, tier in TIERS do
		local button = HudParts.candy(strip, "", function()
			self:jumpTo(tier)
		end, "White", nil)
		button.Name = tier
		local parts = HudParts.candyParts(button)
		local badge = Instance.new("ImageLabel")
		badge.Name = "Badge"
		badge.BackgroundTransparency = 1
		badge.ScaleType = Enum.ScaleType.Fit
		badge.Image = RankBadge.image(tier, 1)
		badge.ZIndex = 2
		badge.Parent = parts.body
		local name = HudParts.text(parts.body, "TierName", K.Text.Body, Ranks.tierName(tier))
		name.TextWrapped = false
		name.ZIndex = 2
		table.insert(self.tierButtons, { tier = tier, button = button, badge = badge, name = name })
	end
end

-- Where a gamepad goes from each control: along the road stop by stop, down to the tier
-- strip, up to the close X; along the strip, and up from a tier to its gate. The panel is a
-- selection group that stops at its edges.
function Roadmap.link(self: any)
	local count = Ranks.count()
	local close = self.closeButton
	for i = 0, count do
		local stop: Stop = self.stops[i]
		local button = stop.button
		button.NextSelectionLeft = if i > 0 then self.stops[i - 1].button else button
		button.NextSelectionRight = if i < count then self.stops[i + 1].button else button
		button.NextSelectionUp = close
		local order = if i == 0 then 1 else Ranks.tierIndex(stop.tier) or 1
		button.NextSelectionDown = self.tierButtons[order].button
	end
	for order, entry in self.tierButtons do
		local button = entry.button
		button.NextSelectionLeft = if order > 1 then self.tierButtons[order - 1].button else button
		button.NextSelectionRight = if order < #self.tierButtons
			then self.tierButtons[order + 1].button
			else button
		button.NextSelectionDown = button
		button.NextSelectionUp = self.stops[Ranks.indexOf(entry.tier) or 1].button
	end
	close.NextSelectionUp = close
	close.NextSelectionRight = close
	close.NextSelectionLeft = close
	close.NextSelectionDown = self.stops[0].button
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
	-- An empty selection box: stops draw their own gold ring, buttons their gold outline.
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
	local card = HudParts.card(panel, "Card")
	card.Size = UDim2.fromScale(1, 1)
	card.ZIndex = 1
	self.card = card
	self:buildHeader(card)
	self:buildCards(card)
	self:buildRoad(card)
	self:buildStrip(card)
	local rules = HudParts.note(card, "Rules", K.Text.Body, rulesText())
	self.rules = rules
	self:link()

	local player = self.player
	local userId = if player then player.UserId else 0
	if userId > 0 then
		local picture = self.picture
		task.spawn(function()
			local ok, content, ready = pcall(function()
				return Players:GetUserThumbnailAsync(
					userId,
					Enum.ThumbnailType.HeadShot,
					Enum.ThumbnailSize.Size150x150
				)
			end)
			if ok and ready and self.alive and picture.Parent then
				picture.Image = content
			end
		end)
	end

	local function resized()
		if self.opened then
			self:layout()
			self:refresh(false)
			self:centre(false)
		end
	end
	table.insert(self.connections, root:GetPropertyChangedSignal("AbsoluteSize"):Connect(resized))
	for _, property in { "AbsoluteSize", "AbsolutePosition" } do
		table.insert(self.connections, area:GetPropertyChangedSignal(property):Connect(resized))
	end
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

function Roadmap.layoutCards(
	self: any,
	leftW: number,
	rightW: number,
	height: number,
	heading: number,
	body: number
)
	local p = math.max(4, round(height * 0.1))
	local inset = round(p * 0.5)
	-- Your rank: the badge poking out of the card's left end, then the words.
	local badge = round(height * R.CardBadgeShare)
	self.currentBadgeHolder.Size = UDim2.fromOffset(badge, badge)
	self.currentBadgeHolder.Position = UDim2.fromOffset(inset, round((height - badge) / 2))
	self.currentBadge:setSize(badge)
	local x = inset + badge + inset
	local columnW = math.max(1, leftW - x - p)
	local nameH = heading + 4
	local rowH = body + 2
	local y = math.max(0, round((height - nameH - rowH * 2) / 2))
	HudParts.setTextSize(self.currentName, heading)
	self.currentName.Position = UDim2.fromOffset(x, y)
	self.currentName.Size = UDim2.fromOffset(columnW, nameH)
	y += nameH
	local barW = round(columnW * 0.5)
	local barH = math.max(8, round(rowH * 0.65))
	self.currentBar.Position = UDim2.fromOffset(x, y + round((rowH - barH) / 2))
	self.currentBar.Size = UDim2.fromOffset(barW, barH)
	HudParts.setTextSize(self.currentXp, body)
	self.currentXp.Position = UDim2.fromOffset(x + barW + 6, y)
	self.currentXp.Size = UDim2.fromOffset(math.max(1, columnW - barW - 6), rowH)
	y += rowH
	HudParts.setTextSize(self.earn, body)
	self.earn.Position = UDim2.fromOffset(x, y)
	self.earn.Size = UDim2.fromOffset(columnW, rowH)
	-- The next reward: its badge, the words, the cash at the right end.
	local nextBadge = round(height * R.NextBadgeShare)
	self.nextBadge.Size = UDim2.fromOffset(nextBadge, nextBadge)
	self.nextBadge.Position = UDim2.fromOffset(inset, round((height - nextBadge) / 2))
	local cash = round(height * R.CashShare)
	self.nextCash.Size = UDim2.fromOffset(cash, cash)
	self.nextCash.Position = UDim2.fromOffset(rightW - p - cash, round((height - cash) / 2))
	local textX = inset + nextBadge + inset
	HudParts.setTextSize(self.nextText, heading)
	self.nextText.Position = UDim2.fromOffset(textX, inset)
	self.nextText.Size = UDim2.fromOffset(math.max(1, rightW - textX - cash - p * 2), height - p)
end

function Roadmap.layoutStrip(self: any, width: number, height: number, gap: number, body: number)
	local count = #self.tierButtons
	local cell = (width - gap * (count - 1)) / count
	local usable = height * (1 - K.ButtonLipShare) -- above the candy's lip
	-- Wide enough: the badge over the tier's name; a phone: the badge alone.
	local named = cell >= R.StripNameMinPx and height >= R.StripNameMinHeightPx
	for order, entry in self.tierButtons do
		entry.button.Position = UDim2.fromOffset(round((cell + gap) * (order - 1)), 0)
		entry.button.Size = UDim2.fromOffset(round(cell), height)
		entry.name.Visible = named
		if named then
			local nameH = body + 2
			local size = math.floor(math.min(usable - nameH - 4, cell - 8))
			entry.badge.AnchorPoint = Vector2.new(0.5, 0)
			entry.badge.Position = UDim2.fromOffset(round(cell / 2), 3)
			entry.badge.Size = UDim2.fromOffset(size, size)
			HudParts.setTextSize(entry.name, body)
			entry.name.Position = UDim2.fromOffset(2, 3 + size)
			entry.name.Size = UDim2.fromOffset(math.max(1, round(cell) - 4), nameH)
		else
			local size = math.floor(math.min(usable - 4, cell - 6))
			entry.badge.AnchorPoint = Vector2.new(0.5, 0.5)
			entry.badge.Position = UDim2.fromOffset(round(cell / 2), round(usable / 2))
			entry.badge.Size = UDim2.fromOffset(size, size)
		end
	end
end

function Roadmap.layoutRoad(
	self: any,
	viewW: number,
	height: number,
	k: number,
	heading: number,
	body: number
)
	local labelGate = heading + 4
	local labelSmall = body + 4
	local function below(size: number): number
		return size * R.LabelDrop + labelGate + size * R.MiniBarShare + 6
	end
	-- A gate as big as the road allows, keeping the tallest column inside it: your picture
	-- and YOU over a gate, its name and the tiny XP bar under it.
	local g = math.min(R.GateMaxPx, height * R.GateShare)
	local least = R.TouchMinPx / R.SmallShare
	while g > least and g * R.AboveShare + below(g) > height do
		g -= 1
	end
	g = math.floor(g)
	local s = math.max(R.TouchMinPx, round(g * R.SmallShare))
	local above = g * R.AboveShare
	local cy = round(math.max(above, (above + height - below(g)) / 2))
	local gap = math.max(4, round(R.StopGapPx * k))
	local edge = round(R.EdgePx * k)
	local chipH = math.max(R.ChipMinPx, round(g * R.ChipShare))
	local function half(stop: Stop): number
		return if stop.gate then g * R.GateHalfShare else stop.size * R.SmallHalfShare
	end

	-- Walk the road left to right: a stop, the chip leading into the next, the next stop.
	local count = Ranks.count()
	local start: Stop = self.stops[0]
	start.size = s
	local x = edge + half(start)
	start.x = x
	local previousHalf = half(start)
	for i = 1, count do
		local stop: Stop = self.stops[i]
		local chip: Chip = self.chips[i]
		stop.size = if stop.gate then g else s
		local ch = if chip.promo then round(chipH * R.PromoChipScale) else chipH
		local textSize = round(ch * R.ChipTextShare)
		local icon = round(ch * R.ChipIconShare)
		local lead = round(ch * 0.15)
		local textX = lead + icon + round(ch * 0.1)
		local textW = math.ceil(textWidth(chip.words, textSize))
		local width = if chip.amount > 0 then textX + textW + round(ch * 0.45) else 0
		local nextHalf = half(stop)
		chip.x = x + previousHalf + gap + width / 2
		x += previousHalf + gap * 2 + width + nextHalf
		stop.x = x
		previousHalf = nextHalf
		chip.pill.Size = UDim2.fromOffset(width, ch)
		chip.pill.Position = UDim2.fromOffset(round(chip.x), cy)
		chip.icon.Size = UDim2.fromOffset(icon, icon)
		chip.icon.Position = UDim2.new(0, lead, 0.5, 0)
		local paid = round(ch * 0.7)
		chip.paid.Size = UDim2.fromOffset(paid, paid)
		chip.paid.Position = UDim2.new(0, lead + round(icon * 0.75), 0.5, round(ch * 0.25))
		HudParts.setTextSize(chip.text, textSize, textSize)
		chip.text.Position = UDim2.fromOffset(textX, 0)
		chip.text.Size = UDim2.fromOffset(textW + 4, ch)
	end
	local canvasW = round(x + previousHalf + edge)

	for i = 0, count do
		local stop: Stop = self.stops[i]
		stop.button.Size = UDim2.fromOffset(stop.size, stop.size)
		stop.button.Position = UDim2.fromOffset(round(stop.x), cy)
		HudParts.setTextSize(stop.label, if stop.gate then heading else body)
		stop.label.Position = UDim2.new(0.5, 0, 0.5, round(stop.size * R.LabelDrop))
		stop.label.Size = UDim2.fromOffset(
			round(math.max(stop.size * 1.5, g * 1.2)),
			if stop.gate then labelGate else labelSmall
		)
	end

	local thick = math.max(8, round(g * R.RoadShare))
	local startX = self.stops[0].x
	self.band.Position = UDim2.fromOffset(round(startX), round(cy - thick / 2))
	self.band.Size = UDim2.fromOffset(round(self.stops[count].x - startX), thick)

	local inset = round(R.ZoneInsetPx * k)
	local radius = UDim.new(0, round(R.ZoneCornerPx * k))
	local bannerW = round(g * R.BannerShare)
	for _, zone: Zone in self.zones do
		local gate: Stop = self.stops[zone.first]
		local last: Stop = self.stops[zone.last]
		local left = gate.x - g * R.GateHalfShare
		zone.frame.Position = UDim2.fromOffset(round(left), inset)
		zone.frame.Size = UDim2.fromOffset(round(last.x + half(last) - left), height - 2 * inset)
		zone.corner.CornerRadius = radius
		zone.banner.Position = UDim2.fromOffset(round(gate.x - bannerW / 2), inset)
		zone.banner.Size = UDim2.fromOffset(bannerW, height - 2 * inset)
		zone.bannerCorner.CornerRadius = radius
	end

	self.scroll.CanvasSize = UDim2.fromOffset(canvasW, 0)
	for _, layer: Frame in self.layers do
		layer.Size = UDim2.fromOffset(canvasW, height)
	end
	local geo: Geo = {
		g = g,
		s = s,
		cy = cy,
		h = height,
		viewW = viewW,
		canvasW = canvasW,
		thick = thick,
		labelGate = labelGate,
		labelSmall = labelSmall,
	}
	self.geo = geo
end

--- Size and place everything from the screen's size. A phone-sized screen gets the whole
--- screen, the title in Roblox's top bar row; a bigger one a capped panel below the bar.
function Roadmap.layout(self: any)
	local size: Vector2 = self.root.AbsoluteSize
	if size.X < 1 or size.Y < 1 then
		return
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
	local function span(pair: { number }): number
		return round(pair[1] + (pair[2] - pair[1]) * t)
	end
	local pad = span(R.PaddingPx)
	local gap = span(R.GapPx)
	local iw = w - 2 * pad
	local titleSize = round(K.Text.Title * R.TitleScale * k)
	local heading = math.max(K.Text.Min, round(K.Text.Heading * k))
	local body = math.max(K.Text.Min, round(K.Text.Body * k))

	-- The title row; on a phone it is Roblox's top bar row, right of Roblox's buttons.
	local headerH, headLeft, headRight = span(R.HeaderPx), 0, 0
	if short then
		headerH = math.max(R.TouchMinPx, barBottom - top - pad)
		headLeft = math.max(0, barLeft - left - pad + gap)
		headRight = math.max(0, left + w - pad - barRight)
	end
	self.header.Position = UDim2.fromOffset(pad, pad)
	self.header.Size = UDim2.fromOffset(iw, headerH)
	self:layoutHeader(iw, headerH, headLeft, headRight, gap, titleSize, body, short)

	-- Bottom up: the rules, the tier strip; top down: the cards; the road takes the rest.
	HudParts.setTextSize(self.rules, body)
	local rulesH = math.ceil(
		TextService:GetTextSize(self.rules.Text, body, FONT, Vector2.new(iw, 1000)).Y
	) + 2
	local rulesY = h - pad - rulesH
	self.rules.Position = UDim2.fromOffset(pad, rulesY)
	self.rules.Size = UDim2.fromOffset(iw, rulesH)
	local stripH = math.max(R.TouchMinPx, span(R.StripPx))
	local stripY = rulesY - math.max(2, round(gap * 0.6)) - stripH
	self.strip.Position = UDim2.fromOffset(pad, stripY)
	self.strip.Size = UDim2.fromOffset(iw, stripH)
	self:layoutStrip(iw, stripH, gap, body)

	local cardsH = span(R.CardsPx)
	local cardsY = pad + headerH + gap
	local leftW = round((iw - gap) * R.CurrentShare)
	self.currentCard.Position = UDim2.fromOffset(pad, cardsY)
	self.currentCard.Size = UDim2.fromOffset(leftW, cardsH)
	self.nextCard.Position = UDim2.fromOffset(pad + leftW + gap, cardsY)
	self.nextCard.Size = UDim2.fromOffset(iw - gap - leftW, cardsH)
	self:layoutCards(leftW, iw - gap - leftW, cardsH, heading, body)

	local roadY = cardsY + cardsH + gap
	local roadH = math.max(R.TouchMinPx * 2, stripY - gap - roadY)
	self.window.Position = UDim2.fromOffset(pad, roadY)
	self.window.Size = UDim2.fromOffset(iw, roadH)
	self.windowCorner.CornerRadius = UDim.new(0, round(R.WindowCornerPx * k))
	local inset = R.WindowInsetPx
	self.scroll.Position = UDim2.fromOffset(inset, inset)
	self.scroll.Size = UDim2.fromOffset(iw - 2 * inset, roadH - 2 * inset)
	self:layoutRoad(iw - 2 * inset, roadH - 2 * inset, k, heading, body)
end

--------------------------------------------------------------------------------------------
-- State (from the player's rank attributes)
--------------------------------------------------------------------------------------------

-- Breathe the next stop (only one at a time, only while open).
function Roadmap.setPulse(self: any, stop: Stop?)
	if self.pulseStop == stop then
		return
	end
	if self.pulse then
		self.pulse.stop()
		self.pulse = nil
	end
	self.pulseStop = stop
	if stop then
		self.pulse = UIAnim.pulse(stop.art)
	end
end

--- Draw the player's rank on the map: every stop's state, your badge, the tags, the road's
--- gold, the paid rewards, the cards and your tier in the strip. `live` animates a change
--- seen while the map is open (the badge pops, the bars slide, the road glides to you).
function Roadmap.refresh(self: any, live: boolean)
	local geo: Geo? = self.geo
	if not geo then
		return
	end
	local player = self.player
	local rated = readNumber(player, "RatedMatches") > 0
	local rank: Rank = Ranks.fromXp(readNumber(player, "RankXp"), rated)
	local current = rank.index
	local count = Ranks.count()
	local peak = math.clamp(math.floor(readNumber(player, "PeakDivision")), current, count)
	local moved = current ~= self.current
	self.current = current
	local here: Stop = self.stops[current]
	local nextStop: Stop? = self.stops[current + 1]

	-- How far into your division you are.
	local fraction = 0
	local xpWords: string
	local width = rank.width
	if current == 0 then
		xpWords = Strings.Ranks.XpOf:format(Format.xp(0), Format.xp(Ranks.width(1) or 0))
	elseif width then
		fraction = math.clamp(rank.xpInDivision / width, 0, 1)
		xpWords = Strings.Ranks.XpOf:format(Format.xp(rank.xpInDivision), Format.xp(width))
	else
		fraction = 1
		xpWords = Strings.Ranks.XpOnly:format(Format.xp(rank.xpInDivision))
	end

	-- The stops: reached (a check), yours, the next, locked (grey and see-through).
	local lockedTint = color(R.LockedTint)
	for i = 0, count do
		local stop: Stop = self.stops[i]
		local locked = i > current + 1
		stop.image.Visible = i ~= current
		stop.image.ImageColor3 = if locked then lockedTint else WHITE
		stop.image.ImageTransparency = if locked then R.LockedTransparency else 0
		HudParts.setTextTransparency(stop.label, if locked then R.LockedTextTransparency else 0)
		stop.check.Visible = i <= current and (i > 0 or current > 0)
		stop.button.ZIndex = if i == current then 3 elseif stop.gate then 2 else 1
	end
	local badge = self.roadBadge
	badge.root.Parent = here.art
	badge:setSize(here.size)
	badge.root.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.root.Position = UDim2.fromScale(0.5, 0.5)
	badge:set(rank.tier, rank.division, live and moved)
	local glowSize = round(here.size * R.GlowScale)
	self.glow.Visible = current > 0 and rank.tier ~= TOP_TIER -- Reyes' badge has its own rays
	self.glow.Size = UDim2.fromOffset(glowSize, glowSize)
	self.glow.Position = UDim2.fromOffset(round(here.x), geo.cy)
	self:setPulse(if self.opened then nextStop else nil)

	-- YOU with your picture over your stop, Next over the next, the tiny XP bar under yours.
	local tagH = math.max(K.Text.Min + 5, round(geo.g * R.TagShare))
	local tagText = math.max(K.Text.Min, round(tagH * 0.72))
	local headSize = round(geo.g * R.HeadShare)
	HudParts.setTextSize(self.youWords, tagText)
	local youW = round(textWidth(P.You, tagText) + tagH)
	self.youTag.Size = UDim2.fromOffset(youW, tagH)
	self.head.Size = UDim2.fromOffset(headSize, headSize)
	self.you.Size = UDim2.fromOffset(math.max(youW, headSize), headSize + tagH - 4)
	self.you.Position = UDim2.fromOffset(round(here.x), round(geo.cy - here.size * R.TopShare))
	self.nextTag.Visible = nextStop ~= nil
	if nextStop then
		HudParts.setTextSize(self.nextWords, tagText)
		self.nextTag.Size = UDim2.fromOffset(round(textWidth(P.Next, tagText) + tagH), tagH)
		self.nextTag.Position =
			UDim2.fromOffset(round(nextStop.x), round(geo.cy - nextStop.size * R.TopShare))
	end
	local labelH = if here.gate then geo.labelGate else geo.labelSmall
	local miniH = math.max(6, round(geo.g * R.MiniBarShare))
	self.miniTrack.Visible = current > 0
	self.miniTrack.Size = UDim2.fromOffset(round(here.size * 0.9), miniH)
	self.miniTrack.Position =
		UDim2.fromOffset(round(here.x), geo.cy + round(here.size * R.LabelDrop) + labelH + 2)
	self.miniFill.Size = UDim2.fromScale(fraction, 1)

	-- The road is gold from the start up to where you are between your stop and the next.
	local startX = self.stops[0].x
	local progress = if nextStop then here.x + (nextStop.x - here.x) * fraction else here.x
	local travelled = math.max(0, round(progress - startX))
	self.travelled.Visible = travelled > 1
	self.travelled.Size = UDim2.new(0, travelled, 1, 0)

	-- Rewards already paid fade with a check; tiers not reached yet are paler.
	for _, chip: Chip in self.chips do
		local claimed = chip.index <= peak
		chip.claimed = claimed
		local fade = if claimed then R.ClaimedTransparency else 0
		chip.paid.Visible = claimed
		chip.pill.BackgroundTransparency = fade
		if chip.edge then
			chip.edge.Transparency = fade
		end
		chip.icon.ImageTransparency = fade
		HudParts.setTextTransparency(chip.text, fade)
	end
	for _, zone: Zone in self.zones do
		local reached = zone.first <= current
		zone.frame.BackgroundTransparency = if reached
			then R.ZoneTransparency
			else R.LockedZoneTransparency
		zone.banner.BackgroundTransparency = if reached
			then R.BannerTransparency
			else R.LockedBannerTransparency
	end
	for _, entry: TierButton in self.tierButtons do
		HudParts.setTone(entry.button, if entry.tier == rank.tier then "Yellow" else "White")
	end

	-- The cards: your rank, and the next money still to earn (a division you already reached
	-- once has paid, so it is the one after your best).
	self.currentBadge:set(rank.tier, rank.division, live and moved)
	self.currentName.Text = Ranks.name(rank)
	self.currentXp.Text = xpWords
	if self.barTween then
		self.barTween:Cancel()
		self.barTween = nil
	end
	local fillSize = UDim2.fromScale(fraction, 1)
	if live then
		local tween = TweenService:Create(
			self.currentFill,
			TweenInfo.new(Config.UI.Progress.CountUpSeconds, Enum.EasingStyle.Quad),
			{ Size = fillSize }
		)
		self.barTween = tween
		tween:Play()
	else
		self.currentFill.Size = fillSize
	end
	if self.currentFade then
		self.currentFade.Color =
			ColorSequence.new(WHITE, WHITE:Lerp(tierColor(rank.tier), R.CardTint))
	end
	local target = peak + 1
	if target > count then
		self.nextBadge.Image = RankBadge.image(TOP_TIER, 1)
		self.nextText.Text = P.TopRank
		self.nextCash.Visible = false
	else
		local tier, division = Ranks.at(target)
		local name = Ranks.name({
			tier = tier,
			division = division,
			index = target,
			xpInDivision = 0,
			width = Ranks.width(target),
		})
		self.nextBadge.Image = RankBadge.image(tier, division)
		self.nextText.Text = P.NextReward:format(name, Format.moneyDelta(Ranks.rewardFor(target)))
		self.nextCash.Visible = true
	end

	local back: Stop = self.lastStop or here
	self.closeButton.NextSelectionDown = back.button
	if live and moved then
		self:scrollTo(here.x)
	end
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
			self:refresh(true)
		end
	end)
end

--------------------------------------------------------------------------------------------
-- Scrolling and input
--------------------------------------------------------------------------------------------

function Roadmap.clampCanvas(self: any, x: number): number
	local geo: Geo? = self.geo
	if not geo then
		return 0
	end
	return math.clamp(x, 0, math.max(0, geo.canvasW - geo.viewW))
end

-- Glide the road until canvas x `contentX` is in the middle.
function Roadmap.scrollTo(self: any, contentX: number)
	local geo: Geo? = self.geo
	if geo then
		self.scrollTarget = self:clampCanvas(contentX - geo.viewW / 2)
	end
end

-- Put your stop in the middle now, and hold it there through the opening pop (the panel's
-- scale is still settling).
function Roadmap.centre(self: any, hold: boolean)
	local geo: Geo? = self.geo
	local here: Stop? = self.stops and self.stops[math.max(self.current, 0)]
	if not geo or not here then
		return
	end
	local x = self:clampCanvas(here.x - geo.viewW / 2)
	self.scroll.CanvasPosition = Vector2.new(x, 0)
	self.scrollTarget = x
	self.holdUntil = if hold then os.clock() + K.Motion.PopSeconds + 0.1 else 0
end

--- Scroll the road to a tier's gate (the tier strip's buttons), with a little bounce.
function Roadmap.jumpTo(self: any, tier: string)
	local stop: Stop? = self.stops[Ranks.indexOf(tier) or 1]
	UISound.play("Click")
	if stop then
		self:scrollTo(stop.x)
		settleStop(stop, R.PressScale, R.PressSeconds)
	end
end

function Roadmap.overRoad(self: any, position: Vector3): boolean
	local corner: Vector2 = self.window.AbsolutePosition
	local size: Vector2 = self.window.AbsoluteSize
	return position.X >= corner.X
		and position.X <= corner.X + size.X
		and position.Y >= corner.Y
		and position.Y <= corner.Y + size.Y
end

function Roadmap.focused(self: any): boolean
	local selected = GuiService.SelectedObject
	return selected ~= nil and selected:IsDescendantOf(self.panel)
end

-- Put the gamepad on your stop.
function Roadmap.focus(self: any)
	local here: Stop? = self.stops[math.max(self.current, 0)]
	if here then
		GuiService.SelectedObject = here.button
	end
end

function Roadmap.onInputBegan(self: any, input: InputObject)
	local code = input.KeyCode
	if code == Enum.KeyCode.ButtonB or code == Enum.KeyCode.Escape then
		self:close()
		return
	end
	local kind = input.UserInputType
	if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
		self.dragMoved = false
		if self:overRoad(input.Position) then
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
		-- The wheel moves the road sideways. Driving it to a target every frame also
		-- overrides any scrolling Roblox does with the wheel by itself.
		if self:overRoad(input.Position) then
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

-- Every frame while open: the road's glide and the gold chips' occasional shine.
function Roadmap.step(self: any, dt: number)
	local geo: Geo? = self.geo
	if not geo then
		return
	end
	local scroll = self.scroll
	local target = self.scrollTarget
	if target then
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
	self.shineClock += dt
	if self.shineClock >= R.ChipShineEvery then
		self.shineClock = 0
		local left = scroll.CanvasPosition.X
		for _, chip: Chip in self.chips do
			if
				chip.promo
				and not chip.claimed
				and chip.pill.Visible
				and chip.x > left
				and chip.x < left + geo.viewW
			then
				UIAnim.shine(chip.pill)
			end
		end
	end
end

function Roadmap.startLoops(self: any)
	self.roadBadge:setShining(true)
	self.currentBadge:setShining(true)
	self.spinner = UIAnim.spin(self.glow, R.GlowDegreesPerSecond)
	self.shineClock = 0
	self.stepper = RunService.RenderStepped:Connect(function(dt)
		self:step(dt)
	end)
	self:setPulse(self.stops[self.current + 1])
end

function Roadmap.stopLoops(self: any)
	if self.roadBadge then
		self.roadBadge:setShining(false)
		self.currentBadge:setShining(false)
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
	-- A gamepad picked up while the map is open lands on your stop.
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

--- Pop the map in, centred on your rank. A gamepad lands on your stop.
function Roadmap.open(self: any)
	if self.opened or not self.alive then
		return
	end
	if not self.built then
		self:build()
	end
	self.opened = true
	self.gui.Enabled = true
	self.current = -1
	self.lastStop = nil
	self:layout()
	self:refresh(false)
	self:centre(true)
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
	for _, stop: Stop in self.stops do
		if stop.lit then
			stop.lit = false
			stop.ring.Visible = false
			settleStop(stop, nil, QUICK)
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
		self.roadBadge:destroy()
		self.currentBadge:destroy()
		self.gui:Destroy()
		self.probe:Destroy()
	end
end

return Roadmap
