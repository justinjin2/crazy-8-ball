--!strict
-- BlockReel: the lucky block opening's spinning reel (LuckyOpening; docs/prompts/ECONOMY_UI_PROMPT.md
-- section 11), Rivals / CS style: a white kit card holding a strip of about 40 cue cards (each the
-- tinted thumbnail on its rarity's dressing, CueThumb) that slides behind a gold marker and slows
-- onto the prize the server already chose.
--
-- - The strip is drawn from the block's odds row at its real odds (BlockOdds.cueOdds, with its
--   Unique rows), but for one showcase card (economy v4 plan section 4): a cue from Epic up out
--   of the same pool with its odds printed on it ("1 in 1,000,000") and a glow in its colour,
--   in the strip's first two-thirds and never within 8 cards of the stop (ReelMath;
--   Reel.Showcase turns it off). It is purely visual (a client Random): the prize is put at a
--   fixed late slot (Reel.PrizeSlot) once the server's answer is known.
-- - The spin eases out over Reel.Seconds (Mythic and Secret: BigSeconds, a longer crawl, the
--   ReelBuild sound and a glow round the window that builds in the prize's colour) and lands at
--   a random offset within the prize card, then glides it to the marker's middle. A soft tick
--   (ReelTick, rate-limited) sounds for each card passing the marker.
-- - As it settles: ReelSettle, the marker turns the prize's colour and the prize card bounces
--   with a thick edge in it; from Rare up (Config.UI.Reel.EffectsFrom, the plan's "win effects
--   only for Rare or better") a glow round the window too (Mythic's drifts through its
--   pastels, Secret's breathes red); after a short hold the reel reports it is done. It can report a
--   set time before the stop too (a Rare or better pull's cutscene starts there, LuckyOpening).
-- - skip() (a tap, A or B; once per spin) races the strip on to the prize in Reel.SkipSeconds.
-- - Each card reads the cue's name and its odds in its rarity's colour (GUI lane, 2026-10-03).
-- - The Dark look (lucky blocks, designer 2026-10-03; Config.LuckyBlocks.UI): no white window or
--   white ends, the strip floats over the dim with its ends fading out (a CanvasGroup), and each
--   card is the cue card (InventoryCard, as in the Cues menu; designer 2026-10-08) with its
--   chance in the corner chip. No card moves (the prize would give itself away).
-- Built in natural pixels inside a ReelFx stage; layout(width) sizes it.
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local ReelMath = require(Shared:WaitForChild("ReelMath"))
local ProgressionRules = Shared:WaitForChild("Progression")
local BlockOdds = require(ProgressionRules:WaitForChild("BlockOdds"))
local Catalog = require(ProgressionRules:WaitForChild("Catalog"))
local Format = require(ProgressionRules:WaitForChild("Format"))
local ReelFx = require(script.Parent.ReelFx)
local CueThumb = require(script.Parent.CueThumb)
local HudParts = require(script.Parent.HudParts)
local InventoryCard = require(script.Parent.InventoryCard)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local C = Config.UI.Reel
local R = C.Reel
local LU = Config.LuckyBlocks.UI
local K = Config.UI.Kit
local INK = HudParts.tone("Ink")
local GOLD = HudParts.tone("Gold")
local WHITE = Color3.new(1, 1, 1)

type Slot = {
	id: string,
	rarity: string,
	frame: Frame,
	edge: UIStroke,
	thumb: Frame, -- the thumbnail (the Dark look: the card's place, its pictures inside)
	dressing: CueThumb.Dressing?, -- the light look's rarity dressing (none in the Dark look)
	name: TextLabel?, -- the light look's words
	odds: TextLabel?,
	cue: boolean, -- the Dark look: a cue card...
	card: any?, -- ...(InventoryCard) once built
	showcase: string?, -- the showcase card's odds ("1 in 1,000,000"); nil on the others
}

local Reel = {}
Reel.__index = Reel

local ODDS_TEXT: { [string]: string } = {} -- a cue's odds in the case being opened ("0.3%")

local function pitch(): number
	return R.CardWidthPx + R.GapPx
end

-- A slot's middle along the strip, in the strip's pixels.
local function centreOf(slot: number): number
	return (slot - 1) * pitch() + R.CardWidthPx / 2
end

-- The odds row's cues (its Unique rows too, less the player's closed ones) with their draw
-- weights: their real odds.
local function pool(oddsId: string, closed: BlockOdds.Closed?): ({ ReelMath.Cue }, number)
	local odds = BlockOdds.cueOdds(oddsId, closed, true)
	if #odds == 0 then
		odds = BlockOdds.cueOdds("Standard")
	end
	local cues, total = {}, 0
	for _, entry in odds do
		ODDS_TEXT[entry.id] = entry.display
		if entry.percent > 0 then
			table.insert(cues, { id = entry.id, rarity = entry.rarity, percent = entry.percent })
			total += entry.percent
		end
	end
	if #cues == 0 then
		table.insert(cues, { id = Catalog.Default, rarity = "Common", percent = 100 })
		total = 100
	end
	return cues, total
end

-- "1 in 1,000,000" for a chance in percent ("" for none).
local function oneInText(percent: number): string
	local n = BlockOdds.oneIn(percent)
	return if n then Strings.LuckyBlocks.OneIn:format(Format.commas(n)) else ""
end

-- A Dark-look card's place: its frame and the outline in the prize's colour that shows once it
-- lands. The cue card itself (buildCueCard) is built a little later, a few cards a frame.
local function makeCueSlot(parent: Instance, index: number, id: string): Slot
	local frame = HudParts.frame(parent, "Card" .. index)
	frame.Size = UDim2.fromOffset(R.CardWidthPx, R.CardHeightPx)
	frame.Position = UDim2.fromOffset((index - 1) * pitch(), 0)
	local units: { number } = Config.UI.CueCard.Units :: any
	local height = math.floor(R.CardWidthPx * units[2] / units[1] + 0.5)
	local outline = HudParts.frame(frame, "Outline")
	outline.AnchorPoint = Vector2.new(0.5, 0.5)
	outline.Position = UDim2.fromScale(0.5, 0.5)
	outline.Size = UDim2.fromOffset(R.CardWidthPx, height)
	outline.ZIndex = 5
	local corner = Config.UI.CueCard.Layout.CornerUnits * R.CardWidthPx / units[1]
	HudParts.corner(outline, math.floor(corner + 0.5))
	local edge = Instance.new("UIStroke")
	edge.Name = "Edge"
	edge.Thickness = R.PrizeStrokePx
	edge.Transparency = 1
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = outline
	return {
		id = id,
		rarity = "",
		frame = frame,
		edge = edge,
		thumb = frame,
		dressing = nil,
		name = nil,
		odds = nil,
		cue = true,
		card = nil,
		showcase = nil,
	}
end

-- A Dark-look card: the cue card (InventoryCard, the Cues menu's, designer 2026-10-08) with the
-- cue's chance in its corner chip, standing still: no card on the reel moves, the prize neither
-- (designer, 2026-10-08: a moving prize would give it away before the stop). YOU GOT's card moves.
local function buildCueCard(slot: Slot)
	local card = InventoryCard.new(slot.frame, { name = "Cue", onPress = function() end })
	card.button.Interactable = false -- a tap on the reel skips it (LuckyOpening)
	card.button.Selectable = false
	card.button.AnchorPoint = Vector2.new(0.5, 0.5)
	card.button.Position = UDim2.fromScale(0.5, 0.5)
	card.button.Size = (slot.edge.Parent :: Frame).Size
	InventoryCard.set(card, {
		cueId = slot.id,
		chance = slot.showcase or ODDS_TEXT[slot.id],
		still = true,
		clear = R.ClearCards,
	})
	slot.card = card
end

-- The showcase card's glow in its rarity's colour, under it (it never moves: no card does).
-- The card's place drops under the other cards, so its glow spills under them, not over.
local function showcaseGlow(slot: Slot)
	slot.frame.ZIndex = 0
	local glow = Instance.new("ImageLabel")
	glow.Name = "ShowcaseGlow"
	glow.BackgroundTransparency = 1
	glow.Image = K.Art.SoftGlow
	glow.ScaleType = Enum.ScaleType.Slice
	local slice: { number } = R.ShowcaseGlowSlice
	glow.SliceCenter = Rect.new(slice[1], slice[2], slice[3], slice[4])
	local g = R.ShowcaseGlowSpreadPx
	glow.SliceScale = 2 * g / R.ShowcaseGlowCornerPx
	glow.ImageColor3 = ReelFx.color(slot.rarity)
	glow.ImageTransparency = R.ShowcaseGlowTransparency
	glow.ZIndex = 0
	-- Round the cue card's outline (the Dark look), else the whole card.
	local box = (slot.edge.Parent :: Frame).Size
	local w = if slot.cue then box.X.Offset else R.CardWidthPx
	local h = if slot.cue then box.Y.Offset else R.CardHeightPx
	glow.Position = UDim2.fromOffset((R.CardWidthPx - w) / 2 - g, (R.CardHeightPx - h) / 2 - g)
	glow.Size = UDim2.fromOffset(w + 2 * g, h + 2 * g)
	glow.Parent = slot.frame
end

-- One card of the strip: a white rounded face dressed in the rarity, the cue's thumbnail on it.
local function makeCard(parent: Instance, index: number, id: string, rarity: string): Slot
	local frame = HudParts.frame(parent, "Card" .. index)
	frame.Size = UDim2.fromOffset(R.CardWidthPx, R.CardHeightPx)
	frame.Position = UDim2.fromOffset((index - 1) * pitch(), 0)
	local fill = HudParts.frame(frame, "Fill")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundTransparency = 0
	fill.BackgroundColor3 = WHITE
	fill.ZIndex = 0
	HudParts.corner(fill, R.CardCornerPx)
	local edge = Instance.new("UIStroke")
	edge.Name = "Edge"
	edge.Color = INK
	edge.Thickness = R.CardStrokePx
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = fill
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Color = ColorSequence.new(WHITE, HudParts.color(K.PanelFade))
	fade.Parent = fill
	local dressing = CueThumb.dress(fill, rarity)
	local side = math.floor(R.CardWidthPx * R.ThumbShare)
	local thumb = CueThumb.new(frame, id)
	thumb.AnchorPoint = Vector2.new(0.5, 0.5)
	thumb.Position = UDim2.fromScale(0.5, R.ThumbCentreShare)
	thumb.Size = UDim2.fromOffset(side, side)
	thumb.ZIndex = 2
	local name = HudParts.text(frame, "Name", R.NameTextPx, CueThumb.cueName(id))
	name.AnchorPoint = Vector2.new(0.5, 0)
	name.Position = UDim2.fromScale(0.5, R.NameTopShare)
	name.Size = UDim2.new(1, -8, 0, R.NameTextPx + 4)
	name.ZIndex = 3
	local odds = HudParts.text(frame, "Odds", R.OddsTextPx, ODDS_TEXT[id] or "")
	odds.AnchorPoint = Vector2.new(0.5, 0)
	odds.Position = UDim2.fromScale(0.5, R.OddsTopShare)
	odds.Size = UDim2.new(1, -8, 0, R.OddsTextPx + 4)
	odds.TextColor3 = CueThumb.accentColor(rarity)
	odds.TextWrapped = false
	odds.ZIndex = 3
	return {
		id = id,
		rarity = rarity,
		frame = frame,
		edge = edge,
		thumb = thumb,
		dressing = dressing,
		name = name,
		odds = odds,
		cue = false,
		card = nil,
		showcase = nil,
	}
end

-- Show another cue on a card (the prize: on a cue card, the only one that moves).
local function dressCard(slot: Slot, id: string, rarity: string)
	slot.id = id
	slot.rarity = rarity
	if slot.cue then
		if slot.card then
			InventoryCard.set(
				slot.card,
				{ cueId = id, chance = ODDS_TEXT[id], still = true, clear = R.ClearCards }
			)
		end
		return -- else it is built with the prize's id
	end
	CueThumb.set(slot.thumb, id)
	local name, odds = slot.name, slot.odds
	if name and odds then
		name.Text = CueThumb.cueName(id)
		odds.Text = ODDS_TEXT[id] or ""
		odds.TextColor3 = CueThumb.accentColor(rarity)
	end
	if slot.dressing then
		slot.dressing.set(rarity)
	end
end

--- Build the reel for the odds row `oddsId` (Config.BlockOdds.List) in `parent` (a stage), its
--- strip drawn at random from that pool. Size it with layout(width); put the prize in with
--- setPrize, then start(). `opts.look` "Dark" is the lucky blocks' look (see the top);
--- `opts.closed`: the player's closed Unique rows (BlockOdds.closedFor), left off the strip.
function Reel.new(
	parent: Instance,
	oddsId: string,
	opts: { look: string?, closed: BlockOdds.Closed? }?
): any
	local self: any = setmetatable({}, Reel)
	local dark = opts ~= nil and opts.look == "Dark"
	self.dark = dark
	self.oddsId = oddsId
	self.random = Random.new()
	self.phase = "Idle" -- Idle, Spinning, Centring, Holding, Done
	self.alive = true
	self.prizeId = nil :: string?
	self.prizeRarity = "Common"
	self.big = false
	self.width = 0
	self.clipWidth = 0
	self.pos = 0 -- where the marker is along the strip, in the strip's pixels
	self.loop = nil :: RBXScriptConnection?
	self.onSettled = nil :: (() -> ())?
	self.onStopping = nil :: (() -> ())?
	self.stoppingLead = 0
	self.lastTick = -math.huge
	self.lastIndex = 0
	self.glowFrom = 0 -- os.clock() when the glow round the window began
	self.glowOn = false
	self.landed = false

	local root = HudParts.frame(parent, "Reel")
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	self.root = root

	-- The glow round the window, under it.
	local halo = ReelFx.halo(root, "Halo")
	halo.ZIndex = 0
	self.halo = halo

	local window = if dark
		then HudParts.frame(root, "Window")
		else HudParts.card(root, "Window", R.CornerPx)
	window.Size = UDim2.fromScale(1, 1)
	window.ZIndex = 1
	self.window = window

	-- The strip, clipped inside the window's straight part (a clip ignores round corners). The
	-- Dark look's clip is a CanvasGroup whose ends fade out over the dim.
	local clip: GuiObject
	if dark then
		local group = Instance.new("CanvasGroup")
		group.Name = "Clip"
		group.BackgroundTransparency = 1
		group.BorderSizePixel = 0
		group.Parent = window
		local ends = Instance.new("UIGradient")
		ends.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(LU.ReelFadeShare, 0),
			NumberSequenceKeypoint.new(1 - LU.ReelFadeShare, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		ends.Parent = group
		clip = group
	else
		clip = HudParts.frame(window, "Clip")
	end
	clip.ClipsDescendants = true
	clip.ZIndex = 1
	self.clip = clip
	local strip = HudParts.frame(clip, "Strip")
	strip.ZIndex = 1
	self.strip = strip

	local cues, total = pool(oddsId, if opts then opts.closed else nil)
	local function rng(n: number): number
		return self.random:NextInteger(1, n)
	end
	-- The showcase: its cue and its place (none when the pool has nothing from Epic up).
	local showcase = if R.Showcase
		then ReelMath.showcaseCue(cues, Catalog.rarityRank, Catalog.rarityRank(R.ShowcaseFrom), rng)
		else nil
	local count = math.max(R.Cards, R.PrizeSlot + 1)
	local showcaseAt = if showcase
		then ReelMath.showcaseSlot(
			rng,
			count,
			R.PrizeSlot,
			R.ShowcaseFirstSlot,
			R.ShowcaseShare,
			R.ShowcaseGapCards
		)
		else nil
	self.showcaseAt = showcaseAt
	self.slots = {} :: { Slot }
	for index = 1, count do
		local chosen = cues[#cues]
		if showcase and index == showcaseAt then
			chosen = showcase
		else
			local pick = self.random:NextNumber(0, total)
			for _, cue in cues do
				pick -= cue.percent
				if pick <= 0 then
					chosen = cue
					break
				end
			end
		end
		local slot = if dark
			then makeCueSlot(strip, index, chosen.id)
			else makeCard(strip, index, chosen.id, chosen.rarity)
		slot.rarity = chosen.rarity
		if showcase and index == showcaseAt then
			local odds = oneInText(chosen.percent)
			slot.showcase = odds
			if slot.odds then
				slot.odds.Text = odds
			end
			showcaseGlow(slot)
		end
		self.slots[index] = slot
	end
	strip.Size = UDim2.fromOffset(#self.slots * pitch(), R.CardHeightPx)
	-- Fetch the strip's pictures now (the case is still in front), so no card spins past blank.
	local function preload()
		local images = {}
		for _, slot in self.slots do
			for _, image in slot.thumb:GetDescendants() do
				if image:IsA("ImageLabel") and image.Image ~= "" then
					table.insert(images, image)
				end
			end
		end
		task.spawn(function()
			pcall(function()
				ContentProvider:PreloadAsync(images)
			end)
		end)
	end
	-- The cue cards: the first ones at once (the window's start), the rest a few a frame while
	-- the reel pops in (all 40 in one frame stalled it for a moment), then their pictures load.
	self.builder = nil :: RBXScriptConnection?
	if dark then
		local next = 1
		local function build(count: number): boolean
			while count > 0 and next <= #self.slots do
				buildCueCard(self.slots[next])
				next += 1
				count -= 1
			end
			return next > #self.slots
		end
		if build(R.EagerCards) then
			preload()
		else
			self.builder = RunService.Heartbeat:Connect(function()
				if not self.alive then
					return
				end
				if build(R.CardsPerFrame) then
					if self.builder then
						self.builder:Disconnect()
						self.builder = nil
					end
					preload()
				end
			end)
		end
	else
		preload()
	end

	-- Soft white ends, so cards slide in and out of view (the Dark look fades its clip instead).
	self.fades = {} :: { Frame }
	local sides: { number } = if dark then {} else { 0, 1 }
	for i, side in sides do
		local fade = HudParts.frame(clip, if side == 0 then "FadeLeft" else "FadeRight")
		fade.BackgroundTransparency = 0
		fade.BackgroundColor3 = WHITE
		fade.AnchorPoint = Vector2.new(side, 0)
		fade.Position = UDim2.fromScale(side, 0)
		fade.ZIndex = 3
		local gradient = Instance.new("UIGradient")
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, if side == 0 then R.FadeEdgeTransparency else 1),
			NumberSequenceKeypoint.new(1, if side == 0 then 1 else R.FadeEdgeTransparency),
		})
		gradient.Parent = fade
		self.fades[i] = fade
	end

	-- The gold marker: a bar down the middle with a tip poking in at the top and the bottom.
	local marker = HudParts.frame(root, "Marker")
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.ZIndex = 3
	self.marker = marker
	local bar = HudParts.frame(marker, "Bar")
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.fromScale(0.5, 0)
	bar.Size = UDim2.new(0, R.MarkerWidthPx, 1, 0)
	bar.BackgroundTransparency = 0
	bar.BackgroundColor3 = GOLD
	bar.ZIndex = 1
	HudParts.corner(bar, math.ceil(R.MarkerWidthPx / 2))
	local barEdge = Instance.new("UIStroke")
	barEdge.Color = INK
	barEdge.Thickness = R.MarkerStrokePx
	barEdge.Parent = bar
	self.bar = bar
	self.tips = {} :: { Frame }
	for i, y in { 0, 1 } do
		local tip = HudParts.frame(marker, if y == 0 then "TipTop" else "TipBottom")
		tip.AnchorPoint = Vector2.new(0.5, 0.5)
		tip.Position = UDim2.fromScale(0.5, y)
		tip.Size = UDim2.fromOffset(R.MarkerTipPx, R.MarkerTipPx)
		tip.Rotation = 45
		tip.BackgroundTransparency = 0
		tip.BackgroundColor3 = GOLD
		tip.ZIndex = 2
		HudParts.corner(tip, R.MarkerTipCornerPx)
		local edge = Instance.new("UIStroke")
		edge.Color = INK
		edge.Thickness = R.MarkerStrokePx
		edge.Parent = tip
		self.tips[i] = tip
	end
	return self
end

--- The reel's height (natural pixels); its width is whatever layout gives it.
function Reel.height(): number
	return R.CardHeightPx + 2 * R.PadYPx
end

-- The slot the spin starts on: far enough in that cards fill the window's left side.
function Reel.startSlot(self: any): number
	local half = self.clipWidth / 2
	return math.max(1, math.ceil(half / pitch()) + 1)
end

--- Size the reel `width` wide (natural pixels). Safe mid-spin: the spin is kept along the strip.
function Reel.layout(self: any, width: number)
	local h = Reel.height()
	local stroke = K.PanelStrokePx
	self.width = width
	self.root.Size = UDim2.fromOffset(width, h)
	local inset = if self.dark then 0 else R.CornerPx
	if self.dark then
		stroke = 0
	end
	self.clipWidth = math.max(1, width - 2 * inset)
	self.clip.Position = UDim2.fromOffset(inset, stroke)
	self.clip.Size = UDim2.fromOffset(self.clipWidth, h - 2 * stroke)
	self.strip.Position = UDim2.fromOffset(0, R.PadYPx - stroke)
	for _, fade in self.fades do
		fade.Size = UDim2.new(0, math.min(R.FadePx, self.clipWidth / 4), 1, 0)
	end
	self.marker.Position = UDim2.fromOffset(width / 2, h / 2)
	self.marker.Size = UDim2.fromOffset(R.MarkerTipPx, h + 2 * R.MarkerOverPx)
	ReelFx.placeHalo(self.halo, Vector2.zero, Vector2.new(width, h), R.HaloSpreadPx)
	if self.phase == "Idle" then
		self.pos = centreOf(self:startSlot())
	end
	self:place()
end

-- Move the strip so `pos` sits under the marker.
function Reel.place(self: any)
	self.strip.Position = UDim2.fromOffset(
		math.floor(self.clipWidth / 2 - self.pos + 0.5),
		R.PadYPx - (if self.dark then 0 else K.PanelStrokePx)
	)
end

--- The reel's entrance, `delay` seconds from now: the window grows in, then each card in view
--- grows from nothing, left to right, one quick step apart. Returns when the last card has
--- started, in seconds from now (the spin can start then). Call after layout.
function Reel.intro(self: any, delay: number): number
	local S = K.Motion.Stagger
	UIAnim.expandIn(self.root, delay, K.Motion.PopFromScale)
	local half = self.clipWidth / 2
	local at = delay + S.GapSeconds
	for index, slot in self.slots do
		local centre = centreOf(index)
		if math.abs(centre - self.pos) <= half + R.CardWidthPx / 2 then
			UIAnim.expandIn(slot.frame, at)
			at += S.GapSeconds
		end
	end
	return at
end

--- Put the server's prize at the prize slot (hidden far along the strip until the spin nears it).
function Reel.setPrize(self: any, cueId: string, rarity: string)
	self.prizeId = cueId
	self.prizeRarity = rarity
	self.big = ReelFx.isBig(rarity)
	dressCard(self.slots[R.PrizeSlot], cueId, rarity)
end

--- Spin onto the prize (setPrize first); `onSettled` runs once, after it has settled and held;
--- `onStopping` (optional) runs once `lead` seconds before the spin stops on it (at once if a
--- skip leaves less than that, at the stop itself at the latest).
function Reel.start(self: any, onSettled: () -> (), onStopping: (() -> ())?, lead: number?)
	if not self.alive or self.phase ~= "Idle" then
		return
	end
	self.onSettled = onSettled
	self.onStopping = onStopping
	self.stoppingLead = lead or 0
	self.phase = "Spinning"
	self.duration = if self.big then R.BigSeconds else R.Seconds
	self.power = if self.big then R.BigEasePower else R.EasePower
	self.from = self.pos
	local spread = R.LandSpread * R.CardWidthPx / 2
	self.offset = self.random:NextNumber(-spread, spread)
	self.to = centreOf(R.PrizeSlot) + self.offset
	self.began = os.clock()
	self.built = false
	self.skipped = false
	self.lastIndex = math.floor(self.pos / pitch())
	self.loop = RunService.RenderStepped:Connect(function()
		local ok, err = pcall(self.step, self)
		if not ok then
			warn("[8ball] BlockReel: " .. tostring(err))
			self:finish()
		end
	end)
end

-- A card edge passed the marker: a soft tick, never faster than TickMinGapSeconds.
function Reel.tick(self: any, now: number)
	local index = math.floor(self.pos / pitch())
	if index ~= self.lastIndex then
		self.lastIndex = index
		if now - self.lastTick >= R.TickMinGapSeconds then
			self.lastTick = now
			UISound.play("ReelTick")
		end
	end
end

-- The glow round the window: building during a big spin's crawl, full once settled.
function Reel.glow(self: any, now: number)
	local rarity = self.prizeRarity
	local share = 0
	if not ReelFx.atLeast(rarity, C.EffectsFrom) then
		share = 0 -- win effects only from Rare up (economy v4 plan section 4)
	elseif self.landed then
		share = 1
	elseif self.big and self.phase == "Spinning" then
		local left = self.began + self.duration - now
		share = math.clamp(1 - left / R.BuildLeadSeconds, 0, 1) * R.BuildGlowShare
	end
	if share <= 0 then
		self.halo.ImageTransparency = 1
		return
	end
	local t = now - self.glowFrom
	local strength = share
	if rarity == "Secret" then
		strength *= 1 - R.SecretBreathDepth * (1 - ReelFx.breath(t, R.BreathSeconds))
	end
	self.halo.ImageColor3 = ReelFx.glowAt(rarity, t)
	self.halo.ImageTransparency = 1 - (1 - R.HaloTransparency) * strength
	if self.landed and rarity == "Mythic" then
		local colour = ReelFx.shimmerAt(t)
		self.bar.BackgroundColor3 = colour
		for _, tip in self.tips do
			tip.BackgroundColor3 = colour
		end
	end
end

function Reel.step(self: any)
	if not self.alive then
		return
	end
	local now = os.clock()
	if self.phase == "Spinning" then
		local u = math.clamp((now - self.began) / self.duration, 0, 1)
		local eased = 1 - (1 - u) ^ self.power
		self.pos = self.from + (self.to - self.from) * eased
		if
			self.big
			and not self.built
			and now >= self.began + self.duration - R.BuildLeadSeconds
		then
			self.built = true
			self.glowFrom = now
			UISound.play("ReelBuild")
		end
		self:tick(now)
		if now >= self.began + self.duration - self.stoppingLead then
			self:stopping()
		end
		if u >= 1 then
			self:land(now)
		end
	elseif self.phase == "Centring" then
		local u = math.clamp((now - self.centreFrom) / R.CentreSeconds, 0, 1)
		self.pos = self.to + (centreOf(R.PrizeSlot) - self.to) * UIAnim.quadOut(u)
		if u >= 1 then
			self.phase = "Holding"
		end
	elseif self.phase == "Holding" then
		if now >= self.holdUntil then
			self:finish()
			return
		end
	end
	self:glow(now)
	self:place()
end

-- The spin stopped on the prize: the settle sound, the marker and the glow in its colour, the
-- prize card bounces with a thick coloured edge; then it glides to the middle and holds.
function Reel.land(self: any, now: number)
	if self.landed then
		return
	end
	self.landed = true
	if not self.built then
		self.glowFrom = now
	end
	UISound.play("ReelSettle")
	local colour = ReelFx.color(self.prizeRarity)
	local slot: Slot = self.slots[R.PrizeSlot]
	slot.edge.Color = colour
	slot.edge.Thickness = R.PrizeStrokePx
	slot.edge.Transparency = 0
	UIAnim.bounce(slot.frame)
	local info = TweenInfo.new(R.MarkerTintSeconds)
	TweenService:Create(self.bar, info, { BackgroundColor3 = colour }):Play()
	for _, tip in self.tips do
		TweenService:Create(tip, info, { BackgroundColor3 = colour }):Play()
	end
	self.phase = "Centring"
	self.centreFrom = now
	local hold = if self.big then R.BigSettleHoldSeconds else R.SettleHoldSeconds
	self.holdUntil = now + R.CentreSeconds + hold
	self:stopping()
end

-- The spin is about to stop (or has): report once.
function Reel.stopping(self: any)
	local stopping = self.onStopping
	self.onStopping = nil
	if stopping then
		stopping()
	end
end

--- One skip per spin (designer, 2026-10-04): the strip does not jump to the prize, it races
--- on from where it is and brakes onto the same spot within Reel.SkipSeconds, so the blur
--- shows the roll was skipped. The landing, centring and hold then play as usual; any
--- further tap (or a tap after it has landed) does nothing.
function Reel.skip(self: any)
	if not self.alive or self.phase ~= "Spinning" or self.skipped then
		return
	end
	self.skipped = true
	local now = os.clock()
	local left = self.began + self.duration - now
	if left <= R.SkipSeconds then
		return -- already in its last moment: skipping would only slow it down
	end
	self.from = self.pos
	self.began = now
	self.duration = R.SkipSeconds
	self.power = R.SkipEasePower
end

-- Settled and held: report once.
function Reel.finish(self: any)
	if self.phase == "Done" then
		return
	end
	self.phase = "Done"
	if self.loop then
		self.loop:Disconnect()
		self.loop = nil
	end
	local done = self.onSettled
	self.onSettled = nil
	if done then
		done()
	end
end

--- Studio checks (GuiQA "luckyReelPeek"): stop the spin where it is and slide slot `index`
--- under the marker. The reel then waits there until it is closed.
function Reel.hold(self: any, index: number)
	if not self.alive or self.slots[index] == nil then
		return
	end
	if self.loop then
		self.loop:Disconnect()
		self.loop = nil
	end
	self.phase = "Holding"
	self.pos = centreOf(index)
	self:place()
end

function Reel.isSpinning(self: any): boolean
	return self.phase ~= "Idle" and self.phase ~= "Done"
end

function Reel.destroy(self: any)
	if not self.alive then
		return
	end
	self.alive = false
	self.onSettled = nil
	self.onStopping = nil
	if self.builder then
		self.builder:Disconnect()
		self.builder = nil
	end
	if self.loop then
		self.loop:Disconnect()
		self.loop = nil
	end
	self.root:Destroy()
end

return Reel
