--!strict
-- GrandOpeningCard: the Shop's Featured page (docs/prompts/SHOP_LIVELY_PROMPT.md section 6):
-- "- FEATURED -" and the Grand Opening card after the designer's target 13b, built from the
-- approved animatic (tools/gui/animatic): the card's navy plate with floating 8-balls, corner
-- fireworks, drifting confetti, bokeh and twinkles; the lucky block (glow, rays, breathe, shine,
-- its crown baked on so it breathes and shines with it, the tilted NEW tag, the sky-blue odds
-- badge and the live "Ends in" timer); the arched GRAND OPENING title with its stars and
-- subtitle; the Beta and Firework Cue cards (their names, UNIQUE pills, odds
-- chips and their own loops); a column per pack: the purple gift square (the Gift Player popup)
-- and the green Robux price, the pack's "3 blocks", then the gold money button.
-- Pictures, places and loop numbers are in Config.UI.GrandOpeningCard, words in Strings
-- (Menus.Shop.Featured), prices and odds in Config (Config.Shop.Deals.GrandOpening,
-- Config.Products.GrandOpening1/3/10, the GrandOpening odds).
--
-- Every piece is registered with the Shop's Stage (ids in Config.UI.Shop.Open) and starts its
-- idle loops as it lands; `keep` holds them until the Shop closes. The card is laid out in the
-- animatic's units, scaled to the page's width (and, given a height, to fit it whole). Text
-- never goes under Layout.MinTextPx. The block opens the odds pop-up (every outcome adding up
-- to 100%, before buying): hover, click, tap, or gamepad A; B, a tap away or leaving closes it.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local StageMath = require(Shared:WaitForChild("StageMath"))
local Progression = Shared:WaitForChild("Progression")
local BlockOdds = require(Progression:WaitForChild("BlockOdds"))
local Format = require(Progression:WaitForChild("Format"))
local ArchTitle = require(script.Parent.ArchTitle)
local HudParts = require(script.Parent.HudParts)
local Quality = require(script.Parent.Quality)
local ShopParts = require(script.Parent.ShopParts)
local Stage = require(script.Parent.Stage)
local UIAnim = require(script.Parent.UIAnim)

local G = Config.UI.GrandOpeningCard
local IMG = G.Images
local LOOP = G.Loops
local L = G.Layout
local FX = Config.UI.Effects
local K = Config.UI.Kit
local DEAL = Config.Shop.Deals.GrandOpening
local PRODUCTS: { [string]: any } = Config.Products.List :: any
local COPY: { [string]: any } = (Strings.Menus.Shop :: any).Featured
local SHOP_COPY: { [string]: any } = Strings.Menus.Shop :: any
local CUES: { [string]: string } = Strings.Items.Cues :: any
local RARITIES: { [string]: string } = Strings.Items.Rarities :: any
local BLOCK_NAMES: { [string]: string } = Strings.LuckyBlocks.Names
local COUNTS = { 1, 3, 10 }
local BETA, FIREWORK = "BetaCue", "FireworkCue"
local B_PRIORITY = Enum.ContextActionPriority.High.Value + 40 -- over the menus' B

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local INK = rgb(K.Colors.Ink)

export type Outcome = { name: string, display: string, percent: number, tint: Color3 }

local GrandOpeningCard = {}
GrandOpeningCard.__index = GrandOpeningCard

--- Every outcome of the Grand Opening block, as the odds pop-up lists them: the rarities bottom
--- first, then the two Unique cues (rarest last). Words from Strings, numbers from Config through
--- BlockOdds (they add up to 100%).
function GrandOpeningCard.outcomes(): { Outcome }
	local list: { Outcome } = {}
	for _, row in BlockOdds.odds("GrandOpening") do
		table.insert(list, {
			name = RARITIES[row.rarity] or row.rarity,
			display = row.display,
			percent = row.percent,
			-- Secret's near-black does not read on a white card: its red glow does.
			tint = if row.rarity == "Secret"
				then rgb(K.SecretGlow)
				else rgb((K.Rarity :: any)[row.rarity] or K.Rarity.Default),
		})
	end
	local uniques = BlockOdds.uniqueRows("GrandOpening")
	table.sort(uniques, function(a, b)
		return a.weight > b.weight
	end)
	for _, row in uniques do
		table.insert(list, {
			name = CUES[row.cue] or row.cue,
			display = row.display,
			percent = row.percent,
			tint = rgb(K.Rarity.Unique),
		})
	end
	return list
end

-- A cue's chance in this block ("0.3%"), for its card's odds chip.
local function cueOdds(cue: string): string
	for _, row in BlockOdds.uniqueRows("GrandOpening") do
		if row.cue == cue then
			return row.display
		end
	end
	return ""
end

--------------------------------------------------------------------------------------------
-- Small builders
--------------------------------------------------------------------------------------------

local function image(parent: Instance, name: string, id: string, z: number): ImageLabel
	local label = Instance.new("ImageLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Image = id
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.ZIndex = z
	label.Parent = parent
	return label
end

local function box(parent: Instance, name: string, z: number): Frame
	local frame = HudParts.frame(parent, name)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.ZIndex = z
	return frame
end

local function label(
	parent: Instance,
	name: string,
	text: string,
	tint: Color3?,
	z: number
): TextLabel
	local made = HudParts.text(parent, name, L.MinTextPx, text, tint)
	made.TextWrapped = false
	made.AnchorPoint = Vector2.new(0.5, 0.5)
	made.ZIndex = z
	return made
end

-- A rounded pill in `tint` with an ink outline and its words.
local function pill(
	parent: Instance,
	name: string,
	text: string,
	tint: Color3,
	z: number
): (Frame, TextLabel)
	local made = HudParts.pill(parent, name, tint)
	made.AnchorPoint = Vector2.new(0.5, 0.5)
	made.ZIndex = z
	local words = label(made, "Words", text, nil, z + 1)
	words.Position = UDim2.fromScale(0.5, 0.5)
	words.Size = UDim2.fromScale(0.92, 0.9)
	return made, words
end

-- A gradient UIStroke round a rounded frame (the cue cards' rims).
local function rim(frame: GuiObject, from: { number }, to: { number }): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Rim"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Color3.new(1, 1, 1)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 25
	gradient.Color = ColorSequence.new(rgb(from), rgb(to))
	gradient.Parent = stroke
	stroke.Parent = frame
	return stroke
end

-- The UIStroke a kit pill wears (to thicken with the layout).
local function strokeOf(object: Instance): UIStroke?
	for _, child in object:GetChildren() do
		if child:IsA("UIStroke") then
			return child
		end
	end
	return nil
end

--------------------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------------------

-- A section's header, "- FEATURED -": the word between two white lines with ink edges.
export type Header = { word: TextLabel, lines: Frame, parts: { Frame } }

--- A section header in `parent` (the Shop's page uses it for the sections under the card).
function GrandOpeningCard.header(parent: Instance, text: string): Header
	local word = label(parent, "HeaderWord", text, nil, 3)
	local lines = box(parent, "HeaderLines", 2)
	local parts: { Frame } = {}
	for _, side in { "Left", "Right" } do
		local line = HudParts.frame(lines, side)
		line.BackgroundTransparency = 0
		line.BackgroundColor3 = Color3.new(1, 1, 1)
		line.AnchorPoint = Vector2.new(0.5, 0.5)
		HudParts.corner(line, 99)
		local edge = Instance.new("UIStroke")
		edge.Color = INK
		edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		edge.Parent = line
		table.insert(parts, line)
	end
	return { word = word, lines = lines, parts = parts }
end

--- Lay a section header out centred on (x, y) at the card's scale `k` (Layout.Featured).
function GrandOpeningCard.layoutHeader(h: Header, x: number, y: number, k: number)
	local F = L.Featured
	local function round(n: number): number
		return math.floor(n + 0.5)
	end
	local px = math.max(L.MinTextPx, round(F.TextUnits * k))
	local fw = math.ceil(ShopParts.textWidth(h.word.Text, px)) + 4
	h.word.Position = UDim2.fromOffset(x, y)
	h.word.Size = UDim2.fromOffset(fw, px + 8)
	HudParts.setTextSize(h.word, px)
	local lineLen = round(F.LineUnits * k)
	local lineGap = round(F.LineGapUnits * k)
	local thick = math.max(4, round(5 * k))
	h.lines.Position = h.word.Position
	h.lines.Size = UDim2.fromOffset(fw + 2 * (lineGap + lineLen), thick + 4)
	for index, line in h.parts do
		local side = if index == 1 then -1 else 1
		line.Position = UDim2.new(0.5, side * (fw / 2 + lineGap + lineLen / 2), 0.5, 0)
		line.Size = UDim2.fromOffset(lineLen, thick)
		local edge = line:FindFirstChildOfClass("UIStroke")
		if edge then
			edge.Thickness = math.max(2, round(2.5 * k))
		end
	end
end

--- The header row's height at the card's scale `k`.
function GrandOpeningCard.headerHeight(k: number): number
	return math.max(L.Featured.MinPx, math.floor(L.Featured.Units * k))
end

export type Actions = {
	robux: (key: string) -> (), -- a Config.Products key (GrandOpening1/3/10)
	money: (count: number) -> (), -- buy `count` blocks with money (Config.Shop.Deals.GrandOpening)
	gift: (key: string) -> (), -- the gift square: gift that Config.Products key to someone here
}

--- Build the Featured page into `parent` (the Shop's page scroller). `actions` buys.
function GrandOpeningCard.new(parent: Instance, actions: Actions): any
	local self: any = setmetatable({}, GrandOpeningCard)
	self.actions = actions
	self.k = 1
	self.titlePx = 0
	self.oddsOpen = false
	self.oddsByHover = false
	self.oddsConnection = nil :: RBXScriptConnection?

	local root = HudParts.frame(parent, "Featured")
	root.ZIndex = 2
	self.root = root

	-- "- FEATURED -"
	self.head = GrandOpeningCard.header(root, COPY.Header)
	self.featured, self.lines = self.head.word, self.head.lines

	-- The card: navy, round, a pale rim; its background clipped inside.
	local card = box(root, "Card", 2)
	card.BackgroundTransparency = 0
	card.BackgroundColor3 = Color3.fromRGB(14, 22, 70)
	self.cardCorner = HudParts.corner(card, 10)
	local cardRim = Instance.new("UIStroke")
	cardRim.Name = "Rim"
	cardRim.Color = rgb(L.Rim)
	cardRim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	cardRim.Parent = card
	self.cardRim = cardRim
	self.card = card
	local back = HudParts.frame(card, "Back")
	back.Size = UDim2.fromScale(1, 1)
	back.ClipsDescendants = true
	back.ZIndex = 1
	self.back = back
	local plate = image(back, "Plate", IMG.Plate, 1)
	plate.AnchorPoint = Vector2.new(0, 0)
	plate.Size = UDim2.fromScale(1, 1)
	plate.ScaleType = Enum.ScaleType.Crop
	self.plateCorner = HudParts.corner(plate, 10)
	self.bokeh = {} :: { ImageLabel }
	local bokehCount = LOOP.BokehCount
	for i = 1, bokehCount do
		local tints = L.BokehTints
		local disc = image(back, "Bokeh" .. i, IMG.BokehDisc, 2)
		disc.ImageColor3 = rgb(tints[(i - 1) % #tints + 1])
		disc.ImageTransparency = 0.82
		table.insert(self.bokeh, disc)
	end
	self.balls = {} :: { ImageLabel }
	for _, row in L.Balls do
		table.insert(self.balls, image(back, row.Picture, (IMG :: any)[row.Picture], 3))
	end
	self.fireworks = {} :: { ImageLabel }
	for _, row in L.Fireworks do
		local burst = image(back, "Firework" .. row.Colour, (FX.Firework :: any)[row.Colour], 4)
		burst.Visible = false
		table.insert(self.fireworks, burst)
	end
	self.twinkles = {} :: { ImageLabel }
	for i = 1, LOOP.TwinkleCount do
		local twinkle = image(back, "Twinkle" .. i, FX.Sparkle.Image, 4)
		twinkle.ImageColor3 = rgb(L.Twinkle.Tint)
		twinkle.Visible = false
		table.insert(self.twinkles, twinkle)
	end
	local drift = HudParts.frame(back, "Drift")
	drift.Size = UDim2.fromScale(1, 1)
	drift.ZIndex = 5
	self.drift = drift

	self:buildBlock()
	self:buildTitle()
	self.beta = self:buildCueCard("Beta")
	self.firework = self:buildCueCard("Firework")
	self:buildButtons()
	self:buildOdds()
	return self
end

function GrandOpeningCard.buildBlock(self: any)
	local card = self.card
	local block = box(card, "Block", 4)
	self.block = block
	local glow = image(block, "Glow", IMG.BlockGlow, 1)
	glow.ImageColor3 = rgb(L.GlowTint)
	glow.ImageTransparency = L.GlowTransparency[1]
	self.glow = glow
	local rays = image(block, "Rays", FX.Rays, 2)
	rays.ImageColor3 = rgb(L.RaysTint)
	rays.ImageTransparency = L.RaysTransparency
	self.rays = rays
	-- The block with its crown baked on (Layout.CrownedBlock, in the block's own units).
	local cb, side = L.CrownedBlock, L.Block[3]
	local picture = image(block, "Picture", IMG.BlockCrowned, 3)
	picture.Position = UDim2.fromScale(0.5 + cb[1] / side, 0.5 + cb[2] / side)
	picture.Size = UDim2.fromScale(cb[3] / side, cb[4] / side)
	self.blockPicture = picture
	local mask = image(block, "Shine", IMG.BlockCrownedMask, 4)
	mask.Position = picture.Position
	mask.Size = picture.Size
	mask.Visible = false -- shown only while its sweep runs (sweep below)
	self.blockMask = mask
	-- The odds badge: a sky-blue "i" that never hides (Roblox's rule: the odds one press away).
	local badge, i = pill(block, "OddsBadge", COPY.OddsBadge, rgb(K.Numbers.Count), 6)
	self.badge, self.badgeText = badge, i
	-- The whole block opens the odds (hover, click, tap, gamepad A).
	local hit = Instance.new("TextButton")
	hit.Name = "OddsHit"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.AutoButtonColor = false
	hit.Selectable = true
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 8
	hit.Parent = block
	self.oddsHit = hit
	hit.MouseEnter:Connect(function()
		if not self.oddsOpen then
			self:showOdds(true, true)
		end
	end)
	hit.MouseLeave:Connect(function()
		if self.oddsOpen and self.oddsByHover then
			self:showOdds(false)
		end
	end)
	hit.Activated:Connect(function()
		if self.oddsOpen and not self.oddsByHover then
			self:showOdds(false)
		else
			self:showOdds(true, false)
		end
	end)

	local tag = box(card, "NewTag", 6)
	tag.Rotation = L.NewTagDegrees
	self.newTag = tag
	local wiggle = box(tag, "Wiggle", 6)
	wiggle.Position = UDim2.fromScale(0.5, 0.5)
	wiggle.Size = UDim2.fromScale(1, 1)
	self.newWiggle = wiggle
	local tagPill, tagWords = pill(wiggle, "Pill", COPY.New, rgb(K.Colors.Red), 6)
	tagPill.Position = UDim2.fromScale(0.5, 0.5)
	tagPill.Size = UDim2.fromScale(1, 1)
	self.newPill, self.newWords = tagPill, tagWords
	self.endsIn = label(card, "EndsIn", "", rgb(L.EndsInColor), 5)
end

function GrandOpeningCard.buildTitle(self: any)
	local card = self.card
	self.title = box(card, "CardTitle", 5)
	self.subtitle = box(card, "Subtitle", 5)
	self.starLeft = image(card, "StarLeft", IMG.StarLeft, 5)
	self.starRight = image(card, "StarRight", IMG.StarRight, 5)
	for _, star in { self.starLeft, self.starRight } do
		star.ScaleType = Enum.ScaleType.Fit
	end
end

-- The title and subtitle are measured letter by letter at a size: rebuilt when it changes.
function GrandOpeningCard.titleAt(self: any, px: number, subPx: number)
	if self.titlePx == px and self.subtitlePx == subPx then
		return
	end
	self.titlePx, self.subtitlePx = px, subPx
	for _, holder in { self.title, self.subtitle } do
		for _, child in holder:GetChildren() do
			child:Destroy()
		end
	end
	local made = ArchTitle.new(self.title, COPY.Title, "Gold", px)
	made.root.AnchorPoint = Vector2.new(0.5, 0.5)
	made.root.Position = UDim2.fromScale(0.5, 0.5)
	self.titleSize = Vector2.new(made.width, made.height)
	local before = string.split(COPY.Subtitle, "%s")[1]
	local from = utf8.len(before) :: number
	local tints: { [number]: Color3 } = {}
	for i = 1, utf8.len(COPY.Limited) :: number do
		tints[from + i] = rgb(K.Numbers.Money)
	end
	local sub = ArchTitle.new(
		self.subtitle,
		string.format(COPY.Subtitle, COPY.Limited),
		"Subtitle",
		subPx,
		tints
	)
	sub.root.AnchorPoint = Vector2.new(0.5, 0.5)
	sub.root.Position = UDim2.fromScale(0.5, 0.5)
	self.subtitleSize = Vector2.new(sub.width, sub.height)
end

-- A cue card ("Beta" or "Firework"): its frame with a gradient rim, its clipped background and loops'
-- pieces, the cue, the name, pills and odds chip.
function GrandOpeningCard.buildCueCard(self: any, which: string): any
	local beta = which == "Beta"
	local c: any = { which = which }
	local frame = box(self.card, which, 4)
	frame.BackgroundTransparency = 0
	frame.BackgroundColor3 = Color3.fromRGB(10, 18, 60)
	c.frame = frame
	c.corner = HudParts.corner(frame, 9)
	local colours = if beta then L.BetaRim else L.FireworkRim
	c.rim = rim(frame, colours[1], colours[2])
	local clip = HudParts.frame(frame, "Clip")
	clip.Size = UDim2.fromScale(1, 1)
	clip.ClipsDescendants = true
	clip.ZIndex = 1
	c.clip = clip
	local bg = image(clip, "Background", if beta then IMG.BetaBg else IMG.FireworkBg, 1)
	bg.AnchorPoint = Vector2.new(0, 0)
	bg.Size = UDim2.fromScale(1, 1)
	bg.ScaleType = Enum.ScaleType.Crop
	c.bgCorner = HudParts.corner(bg, 9)
	if beta then
		c.panels = {}
		for _, row in L.BetaPanels do
			local panel = image(clip, "Panel" .. row[1], (IMG :: any)["BetaPanel" .. row[1]], 2)
			panel.ScaleType = Enum.ScaleType.Fit
			panel.ImageTransparency = 1 - row[5]
			table.insert(c.panels, { label = panel, row = row })
		end
		c.codes = {}
		for index in L.BetaCodeRows do
			local code = image(clip, "Code" .. index, IMG.BetaCodeTile, 2)
			code.ImageColor3 = Color3.fromRGB(120, 220, 255)
			table.insert(c.codes, code)
		end
		c.ring = image(clip, "Ring", IMG.BetaRing, 3)
		c.ring.ImageTransparency = 0.3
		c.motes = HudParts.frame(clip, "Motes")
		c.motes.Size = UDim2.fromScale(1, 1)
		c.motes.ZIndex = 4
	end
	-- The cue: a holder turned to the cue's angle; the cue's own pieces fill it.
	local cue = box(frame, which .. "Cue", 5)
	cue.Rotation = L.CueDegrees
	c.cue = cue
	local function fill(name: string, id: string, z: number): ImageLabel
		local made = image(cue, name, id, z)
		made.Position = UDim2.fromScale(0.5, 0.5)
		made.Size = UDim2.fromScale(1, 1)
		return made
	end
	local picture = if beta then IMG.BetaCue else IMG.FireworkCue
	if beta then
		c.aura = fill("Aura", picture, 1)
		c.aura.Size = UDim2.fromScale(1.04, 1.12)
		c.aura.ImageColor3 = Color3.fromRGB(255, 79, 198)
		c.aura.ImageTransparency = 0.7
	else
		-- A strong yellow glow round the cue, so it stands out of its busy background (designer,
		-- 2026-10-06; tools/gui/cue_glow.py).
		c.aura = fill("Aura", IMG.FireworkCueGlow, 1)
		c.aura.ImageColor3 = rgb(L.FireworkGlow.Tint)
		c.aura.ImageTransparency = L.FireworkGlow.Transparency[1]
	end
	if beta then
		c.callouts = fill("Callouts", IMG.BetaCallouts, 2)
		c.copies = {}
		for index, tint in { Color3.fromRGB(70, 215, 255), Color3.fromRGB(255, 79, 198) } do
			local copy = fill("Glitch" .. index, picture, 3)
			copy.ImageColor3 = tint
			copy.ImageTransparency = 0.4
			copy.Visible = false
			table.insert(c.copies, copy)
		end
	end
	c.picture = fill("Picture", picture, 4)
	c.mask = fill("Pulse", if beta then IMG.BetaCueMask else IMG.FireworkCueMask, 5)
	c.mask.Visible = false
	if not beta then
		-- The gold ribbons: one still frame over the cue, where the render put them; they never
		-- move, only dim and glow (designer, 2026-10-06; tools/gui/firework_still.py).
		local b = L.FireworkRibbons
		c.ribbons = image(cue, "Ribbons", IMG.FireworkRibbons, 6)
		c.ribbons.Position = UDim2.fromScale((b[1] + b[3]) / 2, (b[2] + b[4]) / 2)
		c.ribbons.Size = UDim2.fromScale(b[3] - b[1], b[4] - b[2])
	end
	-- The name in two colours, the pills, the odds chip.
	local name = HudParts.frame(frame, which .. "Name")
	name.ZIndex = 6
	c.name = name
	local words = if beta then COPY.BetaName else COPY.FireworkName
	local tints = if beta then L.BetaColors else L.FireworkColors
	c.nameParts = {}
	for index, text in words do
		local part = label(name, "Part" .. index, text, rgb(tints[index]), 6)
		part.AnchorPoint = Vector2.new(0, 0.5)
		part.TextXAlignment = Enum.TextXAlignment.Left
		table.insert(c.nameParts, part)
	end
	local pills = HudParts.frame(frame, which .. "Pills")
	pills.ZIndex = 6
	c.pills = pills
	c.pillParts = {}
	-- Only UNIQUE (designer, 2026-10-06: no LIMITED pill on the cue cards).
	for _, row in { { COPY.Unique, L.UniqueColor } } do
		local made, text = pill(pills, "Pill", row[1], rgb(row[2]), 6)
		made.AnchorPoint = Vector2.new(0, 0)
		table.insert(c.pillParts, { pill = made, words = text })
	end
	local odds, oddsWords =
		pill(frame, which .. "Odds", cueOdds(if beta then BETA else FIREWORK), rgb(L.OddsColor), 6)
	c.odds, c.oddsWords = odds, oddsWords
	return c
end

-- "3 blocks", "1 block".
local function blocksText(count: number): string
	local words = COPY.Blocks
	return string.format(if count == 1 then words.One else words.Many, count)
end

function GrandOpeningCard.buildButtons(self: any)
	local card = self.card
	self.robuxButtons = {} :: { TextButton }
	self.giftButtons = {} :: { TextButton }
	self.moneyButtons = {} :: { TextButton }
	self.countLabels = {} :: { TextLabel }
	local wasHex = rgb(K.Numbers.Old):ToHex() -- a crossed-out price is red (UI_STYLE 13)
	for index, count in COUNTS do
		local key = DEAL.Products[count]
		local product = PRODUCTS[key]
		local price = string.format(SHOP_COPY.Robux, Format.commas(product.Robux))
		if product.Was then
			-- The old price, struck through, beside the new one.
			price ..= string.format(
				' <font color="#%s"><s>%s</s></font>',
				wasHex,
				Format.commas(product.Was)
			)
		end
		local green = HudParts.candy(card, price, function()
			self.actions.robux(key)
		end, "Green")
		green.Name = "Robux" .. count
		green.AnchorPoint = Vector2.new(0.5, 0.5)
		green.ZIndex = 5
		local parts = HudParts.candyParts(green)
		if parts then
			parts.label.RichText = true
		end
		self.robuxButtons[index] = green
		-- The gift square at its left: a child, so it opens and closes with it.
		local gift = HudParts.candy(green, "", function()
			self.actions.gift(key)
		end, "Purple", "Gift")
		gift.Name = "Gift"
		gift.AnchorPoint = Vector2.new(1, 0.5)
		gift.ZIndex = 5
		self.giftButtons[index] = gift
		self.countLabels[index] = label(card, "Count" .. count, blocksText(count), nil, 5)
		local gold = HudParts.candy(card, Format.money(DEAL.Money[count]), function()
			self.actions.money(count)
		end, "Yellow", "CashSingle")
		gold.Name = "Money" .. count
		HudParts.setIconShare(gold, L.CashIconShare)
		gold.AnchorPoint = Vector2.new(0.5, 0.5)
		gold.ZIndex = 5
		self.moneyButtons[index] = gold
	end
	-- The pack sizes fade in together.
	local counts = HudParts.frame(card, "Counts")
	counts.Size = UDim2.fromScale(1, 1)
	counts.ZIndex = 5
	for _, countLabel in self.countLabels do
		countLabel.Parent = counts
	end
	self.counts = counts
end

-- The odds pop-up: a kit card beside the block, a row per outcome in its colour, the total.
-- Sized in layoutOdds.
function GrandOpeningCard.buildOdds(self: any)
	local list = GrandOpeningCard.outcomes()
	local count = rgb(K.Numbers.Count)
	local card = HudParts.card(self.card, "OddsCard")
	card.ZIndex = 20
	card.Visible = false
	local heading = HudParts.text(card, "Title", L.OddsTitlePx, COPY.OddsTitle)
	heading.ZIndex = 2
	self.oddsHeading = heading
	self.oddsRows = {} :: { { name: TextLabel, value: TextLabel } }
	local total = 0
	for index, row in list do
		local name = HudParts.text(card, "Name" .. index, L.MinTextPx, row.name, row.tint)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextWrapped = false
		name.ZIndex = 2
		local value = HudParts.text(card, "Percent" .. index, L.MinTextPx, row.display, count)
		value.TextXAlignment = Enum.TextXAlignment.Right
		value.TextWrapped = false
		value.ZIndex = 2
		table.insert(self.oddsRows, { name = name, value = value })
		total += row.percent
	end
	local sum = HudParts.note(
		card,
		"Total",
		L.MinTextPx,
		string.format(COPY.OddsTotal, BlockOdds.percentText(total))
	)
	sum.TextXAlignment = Enum.TextXAlignment.Right
	sum.ZIndex = 2
	self.oddsSum = sum
	self.oddsCard = card
end

-- Size the odds pop-up: Layout.OddsRowPx rows, shrunk to fit `maxH` pixels.
function GrandOpeningCard.layoutOdds(self: any, maxH: number)
	local rows = self.oddsRows
	local rowH = math.min(L.OddsRowPx, math.floor(maxH / (#rows + 3.1)))
	local f = rowH / L.OddsRowPx
	local function at(n: number): number
		return math.floor(n * f + 0.5)
	end
	local width = at(L.OddsCardPx)
	local top = at(40)
	local textPx = math.max(L.MinTextPx, at(16))
	self.oddsCard.Size = UDim2.fromOffset(width, at(44) + #rows * rowH + at(30))
	self.oddsHeading.Position = UDim2.fromOffset(at(12), at(8))
	self.oddsHeading.Size = UDim2.fromOffset(width - at(24), at(28))
	HudParts.setTextSize(self.oddsHeading, math.max(L.MinTextPx, at(L.OddsTitlePx)))
	for index, row in rows do
		local y = top + (index - 1) * rowH
		row.name.Position = UDim2.fromOffset(at(14), y)
		row.name.Size = UDim2.fromOffset(width - at(104), rowH)
		row.value.Position = UDim2.fromOffset(width - at(96), y)
		row.value.Size = UDim2.fromOffset(at(82), rowH)
		HudParts.setTextSize(row.name, textPx)
		HudParts.setTextSize(row.value, textPx)
	end
	self.oddsSum.Position = UDim2.fromOffset(at(14), at(44) + #rows * rowH)
	self.oddsSum.Size = UDim2.fromOffset(width - at(28), at(24))
	HudParts.setTextSize(self.oddsSum, textPx)
end

--------------------------------------------------------------------------------------------
-- The odds pop-up
--------------------------------------------------------------------------------------------

--- Show or hide the odds pop-up. `byHover`: opened by the mouse resting on the block (it
--- closes when the mouse leaves); a click, tap or A keeps it until B, a tap away or a press.
function GrandOpeningCard.showOdds(self: any, on: boolean, byHover: boolean?)
	if on == self.oddsOpen and not on then
		return
	end
	self.oddsOpen = on
	self.oddsByHover = on and byHover == true
	if self.oddsConnection then
		self.oddsConnection:Disconnect()
		self.oddsConnection = nil
	end
	ContextActionService:UnbindAction("8ballShopOdds")
	if not on then
		UIAnim.popOut(self.oddsCard)
		return
	end
	UIAnim.popIn(self.oddsCard)
	-- B closes it (before the Shop's own B).
	ContextActionService:BindActionAtPriority("8ballShopOdds", function(_, state)
		if state == Enum.UserInputState.Begin then
			self:showOdds(false)
		end
		return Enum.ContextActionResult.Sink
	end, false, B_PRIORITY, Enum.KeyCode.ButtonB)
	-- A tap or click anywhere off the block and the pop-up closes it.
	self.oddsConnection = UserInputService.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then
			return
		end
		-- The input is below Roblox's top bar; the Shop's ScreenGui ignores that inset.
		local at = Vector2.new(input.Position.X, input.Position.Y) + GuiService:GetGuiInset()
		for _, object in { self.oddsCard, self.oddsHit } do
			local from = object.AbsolutePosition
			local to = from + object.AbsoluteSize
			if at.X >= from.X and at.X <= to.X and at.Y >= from.Y and at.Y <= to.Y then
				return
			end
		end
		self:showOdds(false)
	end)
end

--------------------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------------------

-- The groups (where each part of the animatic's card goes): `o` its origin in the card's
-- units, `s` its scale, `p` where that origin lands.
type Group = { ox: number, oy: number, s: number, px: number, py: number }

--- The page's height at `width` pixels wide (as layout returns, with no height given).
function GrandOpeningCard.heightFor(width: number): number
	local k = width / L.Card[1]
	return math.max(L.Featured.MinPx, math.floor(L.Featured.Units * k))
		+ math.floor(L.Card[2] * k)
		+ 8
end

--- Lay the page out in `width` pixels (and, given, `height`: the card then shrinks to fit it
--- whole, so nothing scrolls); returns its height. The card is centred across the page.
function GrandOpeningCard.layout(self: any, width: number, height: number?): number
	local W, H = L.Card[1], L.Card[2]
	local F = L.Featured
	local k = width / W
	local headerH = math.max(F.MinPx, math.floor(F.Units * k))
	if height then
		k = math.max(0.1, math.min(k, (height - 8 - headerH) / H))
		headerH = math.min(headerH, math.max(F.MinPx, math.floor(F.Units * k)))
	end
	self.k = k
	-- The block's group and the background were placed on the animatic's shorter card.
	local designH = L.DesignHeightUnits
	local same = { ox = 0, oy = 0, s = 1, px = 0, py = 0 }
	local groups: { [string]: Group } = {
		block = { ox = 0, oy = 0, s = 1, px = 0, py = (H - designH) / 2 },
		title = same,
		cards = same,
		buttons = same,
	}
	local cardUnitsH = H
	local cardW, cardH = math.floor(W * k), math.floor(cardUnitsH * k)
	local function round(x: number): number
		return math.floor(x + 0.5)
	end
	local function textPx(units: number, s: number?): number
		return math.max(L.MinTextPx, round(units * (s or 1) * k))
	end
	-- `object`'s centre at (x, y) and its size, in the card's units through `g`.
	local function put(object: GuiObject, g: Group, x: number, y: number, w: number, h: number)
		object.Position = UDim2.fromOffset(
			round((g.px + (x - g.ox) * g.s) * k),
			round((g.py + (y - g.oy) * g.s) * k)
		)
		object.Size = UDim2.fromOffset(round(w * g.s * k), round(h * g.s * k))
	end
	local function measure(text: string, px: number): number
		return math.ceil(ShopParts.textWidth(text, px)) + 4
	end

	self.root.Position = UDim2.fromOffset(math.floor((width - cardW) / 2), 0)
	self.root.Size = UDim2.fromOffset(cardW, headerH + cardH + 8)

	-- "- FEATURED -"
	GrandOpeningCard.layoutHeader(self.head, round(cardW / 2), round(headerH / 2), k)

	-- The card.
	local card = self.card
	card.Position = UDim2.fromOffset(round(cardW / 2), headerH + round(cardH / 2))
	card.Size = UDim2.fromOffset(cardW, cardH)
	local corner = round(L.CornerUnits * k)
	self.cardCorner.CornerRadius = UDim.new(0, corner)
	self.plateCorner.CornerRadius = UDim.new(0, corner)
	self.cardRim.Thickness = math.max(2, round(L.RimUnits * k))
	local yScale = cardUnitsH / designH -- the background spreads over the taller card
	local bg: Group = { ox = 0, oy = 0, s = 1, px = 0, py = 0 }
	local function putBack(object: GuiObject, x: number, y: number, w: number, h: number)
		put(object, bg, x, y * yScale, w, h)
	end
	for i, disc in self.bokeh do
		local size = 22 + ((i - 1) % 4) * 10
		putBack(disc, ((i - 1) * 263) % W, ((i - 1) * 151) % H, size, size)
	end
	for index, row in L.Balls do
		putBack(self.balls[index], row.At[1], row.At[2], row.Units, row.Units)
	end
	for index, row in L.Fireworks do
		putBack(self.fireworks[index], row.At[1], row.At[2], row.Units, row.Units)
	end
	for i, twinkle in self.twinkles do
		local u = L.Twinkle.Units
		putBack(twinkle, ((i - 1) * 397 + 90) % W, ((i - 1) * 211 + 40) % H, u, u)
	end

	-- The block's group.
	local g = groups.block
	put(self.block, g, L.Block[1], L.Block[2], L.Block[3], L.Block[3])
	local blockPx = L.Block[3] * g.s * k
	self.glow.Position = UDim2.fromScale(0.5, 0.5)
	self.glow.Size = UDim2.fromOffset(round(L.Glow[3] * g.s * k), round(L.Glow[3] * g.s * k))
	self.rays.Position = UDim2.fromScale(0.5, 0.5)
	self.rays.Size = UDim2.fromOffset(round(L.Rays[3] * g.s * k), round(L.Rays[3] * g.s * k))
	local badgePx = math.max(L.MinTextPx + 12, round(L.OddsBadge[3] * g.s * k))
	self.badge.Position = UDim2.fromOffset(
		round((L.OddsBadge[1] - L.Block[1] + L.Block[3] / 2) / L.Block[3] * blockPx),
		round((L.OddsBadge[2] - L.Block[2] + L.Block[3] / 2) / L.Block[3] * blockPx)
	)
	self.badge.Size = UDim2.fromOffset(badgePx, badgePx)
	HudParts.setTextSize(self.badgeText, math.max(L.MinTextPx, round(badgePx * 0.7)))
	local tag = L.NewTag
	local tagPx = textPx(L.NewTextUnits, g.s)
	local tagW = math.max(tag[3] * g.s * k, measure(COPY.New, tagPx) + 16)
	local tagH = math.max(tag[4] * g.s * k, tagPx + 10)
	put(self.newTag, g, tag[1], tag[2], 0, 0)
	self.newTag.Size = UDim2.fromOffset(round(tagW), round(tagH))
	HudParts.setTextSize(self.newWords, tagPx)
	local endsPx = textPx(L.EndsInUnits, g.s)
	put(self.endsIn, g, L.EndsIn[1], L.EndsIn[2], 0, 0)
	self.endsIn.Size = UDim2.fromOffset(round(364 * g.s * k), endsPx + 8)
	HudParts.setTextSize(self.endsIn, endsPx)

	-- The title's group.
	g = groups.title
	local titlePx = textPx(L.TitleUnits, g.s)
	local subPx = textPx(L.SubtitleUnits, g.s)
	self:titleAt(titlePx, subPx)
	put(self.title, g, L.Title[1], L.Title[2], 0, 0)
	self.title.Size = UDim2.fromOffset(self.titleSize.X, self.titleSize.Y)
	put(self.subtitle, g, L.Subtitle[1], L.Subtitle[2], 0, 0)
	self.subtitle.Size = UDim2.fromOffset(self.subtitleSize.X, self.subtitleSize.Y)
	-- The stars sit just outside the title, however wide the words came out.
	local half = self.titleSize.X / 2 / k / g.s
	put(
		self.starLeft,
		g,
		L.Title[1] - half - L.StarLeft[3] * 0.45,
		L.StarLeft[2],
		L.StarLeft[3],
		L.StarLeft[3]
	)
	put(
		self.starRight,
		g,
		L.Title[1] + half + L.StarRight[3] * 0.45,
		L.StarRight[2],
		L.StarRight[3],
		L.StarRight[3]
	)

	-- The cue cards.
	g = groups.cards
	for _, c in { self.beta, self.firework } do
		local R = if c.which == "Beta" then L.Beta else L.Firework
		put(c.frame, g, R[1] + R[3] / 2, R[2] + R[4] / 2, R[3], R[4])
		local w, h = R[3] * g.s * k, R[4] * g.s * k
		local cornerPx = round(L.CueCardCornerUnits * g.s * k)
		c.corner.CornerRadius = UDim.new(0, cornerPx)
		c.bgCorner.CornerRadius = UDim.new(0, cornerPx)
		c.rim.Thickness = math.max(2, round(L.CueCardRimUnits * g.s * k))
		local share = if c.which == "Beta" then L.CueShare else L.FireworkCueShare
		local cueW = w * share[3]
		c.cue.Position = UDim2.fromOffset(round(w * share[1]), round(h * share[2]))
		c.cue.Size = UDim2.fromOffset(round(cueW), round(cueW * 284 / 1024))
		-- Name, pills, odds chip.
		local nameUnits = if c.which == "Beta" then L.BetaNameUnits else L.FireworkNameUnits
		local namePx = textPx(nameUnits, g.s)
		local x = round(L.NameAt[1] * g.s * k)
		c.name.Position = UDim2.fromOffset(x, round(L.NameAt[2] * g.s * k - namePx / 2 - 2))
		local at = 0
		for _, part in c.nameParts do
			local pw = measure(part.Text, namePx)
			part.Position = UDim2.fromOffset(at, round(namePx / 2 + 2))
			part.Size = UDim2.fromOffset(pw, namePx + 4)
			HudParts.setTextSize(part, namePx)
			at += pw - 4
		end
		c.name.Size = UDim2.fromOffset(at, namePx + 4)
		local pillPx = math.max(L.PillMinTextPx, round(L.PillTextUnits * g.s * k))
		local pillH = math.max(round(L.PillUnits[2] * g.s * k), pillPx + 6)
		c.pills.Position = UDim2.fromOffset(x, round(L.NameAt[2] * g.s * k + namePx / 2 + 4))
		local px = 0
		for _, p in c.pillParts do
			local pw = math.max(round(L.PillUnits[1] * g.s * k), measure(p.words.Text, pillPx) + 10)
			p.pill.Position = UDim2.fromOffset(px, 0)
			p.pill.Size = UDim2.fromOffset(pw, pillH)
			HudParts.setTextSize(p.words, pillPx)
			px += pw + round(L.PillGapUnits * g.s * k)
		end
		c.pills.Size = UDim2.fromOffset(px, pillH)
		local chip = L.OddsChip
		local oddsPx = textPx(L.OddsTextUnits, g.s)
		local ow = math.max(round(chip[1] * g.s * k), measure(c.oddsWords.Text, oddsPx) + 16)
		local oh = math.max(round(chip[2] * g.s * k), oddsPx + 8)
		c.odds.Position = UDim2.fromOffset(round(w - 6 - ow / 2), round(h - 6 - oh / 2))
		c.odds.Size = UDim2.fromOffset(ow, oh)
		HudParts.setTextSize(c.oddsWords, oddsPx)
		if c.panels then
			for _, p in c.panels do
				local row = p.row
				local pw = round(row[4] / 1120 * w)
				p.label.Position =
					UDim2.fromOffset(round(row[2] / 1120 * w), round(row[3] / 660 * h))
				p.label.Size = UDim2.fromOffset(pw, pw)
			end
			local ring = round(h * L.BetaRingShare)
			c.ring.Position = UDim2.fromOffset(round(w * 0.53), round(h / 2))
			c.ring.Size = UDim2.fromOffset(ring, ring)
			local codeH = math.max(4, round(w * 24 / 512))
			for index, code in c.codes do
				local row = L.BetaCodeRows[index]
				local y = row[1] * g.s * k
				code.Position = UDim2.fromOffset(round(w / 2), round(if y >= 0 then y else h + y))
				code.Size = UDim2.fromOffset(round(w), codeH)
				code.ImageTransparency = 1 - row[3]
			end
		end
		for _, stroke in { strokeOf(c.odds), strokeOf(c.pillParts[1].pill) } do
			if stroke then
				stroke.Thickness = math.max(2, round(4 * g.s * k))
			end
		end
	end

	-- The buttons: a column per pack.
	g = groups.buttons
	-- The Robux row a little bigger than the money row (designer, 2026-10-06).
	local greenPx = textPx(L.GreenTextUnits, g.s)
	local goldPx = textPx(L.GoldTextUnits, g.s)
	local rowPx = math.max(24, round(L.RowGreenUnits * g.s * k)) -- touch areas are 44 (setMinHit)
	local goldRowPx = math.max(24, round(L.RowGoldUnits * g.s * k))
	local giftGap = round(L.GiftGapUnits * g.s * k)
	local giftPx = math.max(20, round(L.GiftUnits * g.s * k))
	local countPx = textPx(L.CountTextUnits, g.s)
	local touch = Config.UI.Menu.Frame.TouchMinPx
	for index in COUNTS do
		local left = L.ButtonX + (index - 1) * (L.ButtonUnits + L.ButtonGapUnits)
		local x = left + L.ButtonUnits / 2
		-- The gift square and the green price share the top row.
		local green: TextButton = self.robuxButtons[index]
		local gift: TextButton = self.giftButtons[index]
		put(green, g, x, L.RowGreen + L.RowGreenUnits / 2, L.ButtonUnits, L.RowGreenUnits)
		local columnW = green.Size.X.Offset
		local greenW = columnW - giftPx - giftGap
		green.Position += UDim2.fromOffset(round((giftPx + giftGap) / 2), 0)
		green.Size = UDim2.fromOffset(greenW, rowPx)
		HudParts.setButtonTextSize(green, greenPx)
		gift.Position = UDim2.new(0, -giftGap, 0.5, 0)
		gift.Size = UDim2.fromOffset(giftPx, giftPx)
		local countLabel = self.countLabels[index]
		put(countLabel, g, x, L.CountY, L.ButtonUnits, 0)
		countLabel.Size = UDim2.fromOffset(countLabel.Size.X.Offset, countPx + 6)
		HudParts.setTextSize(countLabel, countPx)
		local gold: TextButton = self.moneyButtons[index]
		put(gold, g, x, L.RowGold + L.RowGoldUnits / 2, L.ButtonUnits, L.RowGoldUnits)
		gold.Size = UDim2.fromOffset(gold.Size.X.Offset, goldRowPx)
		HudParts.setButtonTextSize(gold, goldPx)
		for _, button in { green, gift, gold } do
			HudParts.setMinHit(button, touch)
		end
	end

	-- The odds pop-up: beside the block, inside the card.
	self:layoutOdds(cardH - 16)
	local blockRight = (groups.block.px + (364 - groups.block.ox) * groups.block.s) * k
	self.oddsCard.Position = UDim2.fromOffset(
		round(math.min(blockRight, cardW - self.oddsCard.Size.X.Offset - 8)),
		round(math.max(8, (cardH - self.oddsCard.Size.Y.Offset) / 2))
	)
	return headerH + cardH + 8
end

--------------------------------------------------------------------------------------------
-- The timer
--------------------------------------------------------------------------------------------

--- Show what the shop state says: the time left on the deal ("Ends in 20d 23h"), hidden when
--- the deal is not open.
function GrandOpeningCard.refresh(self: any, state: any)
	local deals = if type(state) == "table" and type(state.deals) == "table"
		then state.deals
		else {}
	local deal = deals.GrandOpening
	local open = type(deal) == "table" and deal.open == true and type(deal.endsAt) == "number"
	self.endsIn.Visible = open
	if open then
		self.endsIn.Text =
			string.format(COPY.EndsIn, StageMath.timeLeft(deal.endsAt - ShopParts.now(), COPY))
	end
end

--------------------------------------------------------------------------------------------
-- Stage and the idle loops
--------------------------------------------------------------------------------------------

-- The block's breathe: its pictures' window zooms inside their clear border (gate 1: smooth);
-- the crowned block and its shine silhouette together, so the crown and shine breathe with it.
-- `px` is their width, height and border in pixels (Layout.CrownedBlockPx).
local function breathe(pictures: { ImageLabel }, px: { number }): UIAnim.Handle
	local w, h = px[1], px[2]
	-- The border shared by length, so a wide picture keeps its shape.
	local per = px[3] / math.max(w, h)
	local phase = Random.new():NextNumber(0, math.pi * 2)
	local handle = UIAnim.loop(pictures[1], function(clock)
		local scale = if UIAnim.reduced()
			then 1
			else 1 + LOOP.BreatheScale * math.sin(
				2 * math.pi * clock / LOOP.BreatheSeconds + phase
			)
		local sw, ow = StageMath.breatheRect(w, w * per, scale)
		local sh, oh = StageMath.breatheRect(h, h * per, scale)
		for _, picture in pictures do
			picture.ImageRectSize = Vector2.new(sw, sh)
			picture.ImageRectOffset = Vector2.new(ow, oh)
		end
	end)
	return {
		stop = function()
			handle.stop()
			for _, picture in pictures do
				picture.ImageRectSize = Vector2.zero
				picture.ImageRectOffset = Vector2.zero
			end
		end,
	}
end

-- A shine across a button's face every `every` seconds, starting `delay` in.
local function buttonShine(button: TextButton, every: number, delay: number): UIAnim.Handle
	local body = button:FindFirstChild("Body")
	local face = body and body:FindFirstChild("Face") :: GuiObject?
	local last = -1
	return UIAnim.loop(button, function(clock)
		if face == nil or UIAnim.reduced() or clock < delay then
			return
		end
		local n = (clock - delay) // (every / math.max(0.25, Quality.rate()))
		if n ~= last then
			last = n
			UIAnim.shine(face)
		end
	end)
end

-- The Grand Opening card's mini fireworks: one at a random spot every so often, in turn through
-- the five colours, at half speed (designer).
local function miniFireworks(clip: Frame, k: number): UIAnim.Handle
	local colours = { "Gold", "Pink", "Cyan", "Purple", "Orange" }
	local random = Random.new()
	local next, n = 0, 0
	return UIAnim.loop(clip, function(clock)
		if clock < next or UIAnim.reduced() then
			return
		end
		next = clock + LOOP.FireworkBurstEvery / math.max(0.25, Quality.rate())
		n += 1
		local size = math.floor((140 + random:NextNumber(0, 120)) / 2 * k)
		local burst = image(clip, "Mini", "", 2)
		burst.Size = UDim2.fromOffset(size, size)
		burst.Position = UDim2.fromScale(random:NextNumber(0.05, 0.95), random:NextNumber(0.1, 0.9))
		UIAnim.flipbook(burst, FX.Firework, {
			image = (FX.Firework :: any)[colours[(n - 1) % #colours + 1]],
			fps = LOOP.FireworkBurstFps,
			done = function()
				burst:Destroy()
			end,
		})
	end)
end

-- A light sweeping across a picture's shape (its white silhouette `mask`, hidden otherwise).
local function sweep(
	mask: ImageLabel,
	every: number,
	seconds: number,
	strength: number
): UIAnim.Handle
	mask.Visible = true
	local handle = UIAnim.maskedSweep(mask, every, seconds, strength)
	return {
		stop = function()
			handle.stop()
			mask.Visible = false
		end,
	}
end

-- Many handles as one.
local function all(list: { UIAnim.Handle }): UIAnim.Handle
	return {
		stop = function()
			for _, h in list do
				h.stop()
			end
		end,
	}
end

--- Register every piece with `stage` (ids as Config.UI.Shop.Open); `keep(handle)` holds a
--- piece's idle loops (started as it lands) until the Shop closes.
function GrandOpeningCard.register(self: any, stage: Stage.Stage, keep: (UIAnim.Handle) -> ())
	local low = Quality.isLow
	stage:add("Featured", self.featured)
	stage:add("FeaturedLines", self.lines)
	stage:add("Card", self.card, function()
		local k = self.k
		local list: { UIAnim.Handle } = {}
		for i, disc in self.bokeh do
			if not low() or i % 2 == 1 then
				table.insert(list, UIAnim.glowPulse(disc, 0.76, 0.98, 4.8 + (i % 3)))
			end
		end
		for index, ball in self.balls do
			local row = L.Balls[index]
			local px = LOOP.BallFloatPx
			table.insert(
				list,
				UIAnim.float(
					ball,
					row.ImagePx,
					Vector2.new(px[1], px[2]) * k,
					2 * math.pi / row.Speed
				)
			)
		end
		for index, burst in self.fireworks do
			if not low() or index % 2 == 1 then
				local colour = L.Fireworks[index].Colour
				table.insert(
					list,
					UIAnim.burstLoop(burst, FX.Firework, LOOP.CornerFireworkEvery, {
						image = (FX.Firework :: any)[colour],
					})
				)
			end
		end
		local open = Config.UI.Shop.Open
		for i, twinkle in self.twinkles do
			if open.Twinkles and (not low() or i % 2 == 1) then
				table.insert(list, UIAnim.burstLoop(twinkle, FX.Sparkle, 2.2 + (i - 1) * 0.37))
			end
		end
		table.insert(
			list,
			if not open.Streamers
				then all({})
				else UIAnim.confettiDrift(
					self.drift,
					IMG.ConfettiSquare,
					L.Confetti,
					math.floor(L.ConfettiUnits * k),
					256,
					LOOP.ConfettiFallPxPerSecond * k
				)
		)
		-- Party poppers from the card's bottom corners as it opens (Config.UI.Shop.Open).
		if open.Poppers and not low() and not UIAnim.reduced() then
			for index, colour in { "Gold", "Pink" } do
				local size = math.floor(260 * k)
				local popper = image(self.card, "Popper", "", 3)
				popper.Size = UDim2.fromOffset(size, size)
				popper.Position = UDim2.fromScale(if index == 1 then 0.02 else 0.98, 0.98)
				UIAnim.flipbook(popper, FX.Firework, {
					image = (FX.Firework :: any)[colour],
					done = function()
						popper:Destroy()
					end,
				})
			end
		end
		keep(all(list))
	end)
	stage:add("Block", self.block, function()
		keep(all({
			UIAnim.glowPulse(
				self.glow,
				L.GlowTransparency[1],
				L.GlowTransparency[2],
				LOOP.GlowPulseSeconds
			),
			UIAnim.turn(self.rays, LOOP.RaysTurnPerSecond),
			breathe({ self.blockPicture, self.blockMask }, L.CrownedBlockPx),
			sweep(self.blockMask, LOOP.BlockShineEvery, 0.7, 0.75),
		}))
	end)
	stage:add("NewTag", self.newTag, function()
		keep(UIAnim.shake(self.newWiggle, "NewTag"))
	end)
	stage:add("CardTitle", self.title)
	stage:add("StarLeft", self.starLeft, function()
		keep(UIAnim.turn(self.starLeft, 0, L.StarRockDegrees, L.StarRockSeconds))
	end)
	stage:add("StarRight", self.starRight, function()
		keep(UIAnim.turn(self.starRight, 0, -L.StarRockDegrees, L.StarRockSeconds))
	end)
	stage:add("Subtitle", self.subtitle)
	for _, c in { self.beta, self.firework } do
		local which = c.which
		stage:add(which, c.frame, function()
			local list: { UIAnim.Handle } = {}
			if which == "Beta" then
				for index, p in c.panels do
					if not low() or index <= 5 then
						local strength = p.row[5]
						table.insert(
							list,
							UIAnim.glowPulse(
								p.label,
								1 - strength,
								1 - strength * 0.45,
								LOOP.BetaPanelWaveSeconds
							)
						)
					end
				end
				table.insert(list, UIAnim.turn(c.ring, LOOP.BetaRingTurnPerSecond))
				for index, code in c.codes do
					local row = L.BetaCodeRows[index]
					table.insert(
						list,
						UIAnim.scrollTile(
							code,
							512,
							c.frame.Size.X.Offset,
							LOOP.BetaCodePxPerSecond * self.k,
							Vector2.new(row[2], 0),
							1024
						)
					)
				end
				table.insert(
					list,
					UIAnim.scanLine(c.clip, Color3.fromRGB(70, 215, 255), LOOP.BetaScanEvery, 1.2)
				)
				if not low() then
					table.insert(
						list,
						UIAnim.confettiDrift(
							c.motes,
							{ IMG.BetaMote },
							L.BetaMotes,
							math.max(4, math.floor(8 * self.k)),
							48,
							-14 * self.k
						)
					)
				end
			else
				table.insert(list, miniFireworks(c.clip, self.k))
			end
			keep(all(list))
		end)
		stage:add(which .. "Name", c.name)
		stage:add(which .. "Pills", c.pills)
		stage:add(which .. "Odds", c.odds)
		stage:add(which .. "Cue", c.cue, function()
			local list: { UIAnim.Handle } = {
				if which == "Beta"
					then UIAnim.glowPulse(c.aura, 0.55, 0.85, 3)
					else UIAnim.glowPulse(
						c.aura,
						L.FireworkGlow.Transparency[1],
						L.FireworkGlow.Transparency[2],
						L.FireworkGlow.PulseSeconds
					),
				sweep(c.mask, if which == "Beta" then LOOP.BetaPulseEvery else 4, 1, 0.8),
			}
			if which == "Beta" then
				table.insert(list, UIAnim.glowPulse(c.callouts, 0.05, 0.25, 0.9))
				table.insert(
					list,
					UIAnim.glitch(c.picture, c.copies, LOOP.BetaGlitchEvery, 0.14, 3)
				)
			else
				table.insert(
					list,
					UIAnim.glowPulse(
						c.ribbons,
						0,
						LOOP.RibbonDimTransparency,
						LOOP.RibbonPulseSeconds
					)
				)
			end
			keep(all(list))
		end)
	end
	for index, count in COUNTS do
		local green, gold = self.robuxButtons[index], self.moneyButtons[index]
		stage:add("Robux" .. count, green, function()
			keep(buttonShine(green, LOOP.ButtonShineEvery, (index - 1) * 0.35))
		end)
		-- The money buttons never shine (designer, 2026-10-06: only the Robux options).
		stage:add("Money" .. count, gold)
	end
	stage:add("Counts", self.counts)
	stage:add("EndsIn", self.endsIn)
end

--- The Shop closed: the odds pop-up goes too.
function GrandOpeningCard.closed(self: any)
	if self.oddsOpen then
		self:showOdds(false)
	end
end

--- The bought-blocks notice: "Your Grand Opening Lucky Block is in your hotbar!".
function GrandOpeningCard.boughtText(count: number): string
	local name = BLOCK_NAMES.GrandOpening or "GrandOpening"
	if count > 1 then
		return string.format(COPY.BoughtMany, count, name)
	end
	return string.format(COPY.BoughtOne, name)
end

return GrandOpeningCard
