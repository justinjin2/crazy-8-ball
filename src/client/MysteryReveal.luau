--!strict
-- MysteryReveal: the climb screen (the Mystery block's upgrade screen, designer, 2026-10-07,
-- like Star Drop but our own; restyled to pick "mystery_reveal B", the Track, 2026-10-08;
-- every unclimbed block's since economy v5, 2026-10-09; Config.LuckyBlocks.Reveal). A tap on a
-- ready unclimbed block's OPEN! slot jumps its 2D icon out of the hotbar at the screen while
-- the world blurs; it lands as itself, its name over it ("MYSTERY": designer, 2026-10-09,
-- "before you even click on it its still a mystery block"; a tier block shows its tier, lit on
-- the ladder: it climbs from there), and floats there with its particles over a glow and
-- turning rays. The first press shows its starting tier (its own, or higher); each of the
-- other three may lift it one tier, never down. At the top a white pill counts the presses
-- ("Rare Lucky Block - 2 / 4"; designer, 2026-10-09: no lines under it, the block takes their
-- room, and no pity here); along the bottom the climb's ladder of seven tiers, the Secret on
-- top (a dark silhouette with a red "?": there is no Secret block), its line filled up to the
-- tier on show, that tier's block raised with an arrow over it. Each press (a tap, a click, A, Space or
-- Enter) squashes the block; a press that lifts the tier bounces it, then it turns into the
-- next block with an impact (a white flash, a screen shake and a burst; designer, 2026-10-07:
-- no spin), its name slamming in over it ("EPIC!"; Standard has no "!") as the ladder's line
-- reaches it. A dot
-- under the block fills per press in the colour that press showed; the white Tap! button under
-- the dots says what to do. After the last press "Tap to collect" (or a few seconds) shrinks
-- the screen and the block jumps back into its hotbar slot, the climbed block on its tier's
-- timer. A Mystery's presses are its roll instead (economy v5.1): it lands back as the
-- unclimbed block it turned into, showing OPEN!, and climbs when that block is opened. A climb
-- that reached the Secret leaves no block: a moment after its last press the
-- screen hands over to the Secret's pull cutscene (deps.secret). Sounds (designer, 2026-10-09): a
-- whoosh as it opens, a rising shimmer on a press that lifts the tier, a soft shimmer on one
-- that only shakes it (Config.Audio.Ui.Mystery*).
--
-- The server decides everything first (BlockRequest "Reveal": the tier, with a Mystery block's
-- pity, and the path of the presses, BlockDrop.path: one entry per press, the start then
-- climbs only) and the block is already that tier's climbed block in the save (a Mystery's: the
-- unclimbed block it turned into; or the Secret cue the player's); this screen only plays the
-- path. Leaving or closing early loses nothing.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local LuckyBlocks = require(Shared:WaitForChild("Progression"):WaitForChild("LuckyBlocks"))
local HudParts = require(script.Parent.HudParts)
local Quality = require(script.Parent.Quality)
local ReelFx = require(script.Parent.ReelFx)
local ScreenBlur = require(script.Parent.ScreenBlur)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local R = Config.LuckyBlocks.Reveal
local LD = R.Ladder
local IMAGES: { [string]: string } = R.Images :: any
local TIERS: { [string]: any } = R.Tiers :: any
local ORDER: { string } = Config.BlockOdds.Climb.Tiers -- the ladder, Standard to the Secret
local W = Strings.LuckyBlocks.Reveal
local KIND_TITLES: { [string]: string } = W.Kinds :: any
local SHORT: { [string]: string } = Strings.LuckyBlocks.Short :: any
local NAMES: { [string]: string } = Strings.LuckyBlocks.Names :: any
local SECRET = "Secret" -- the ladder's top: no block, its cue at once
local CLICKS: number = Config.BlockOdds.Drop.Upgrade.Clicks
local FONT: Enum.Font = (Enum.Font :: any)[Config.UI.Kit.Font]
local ACTION = "MysteryRevealPress"
local SHAKE = "MysteryRevealShake"
local MAX_PARTICLES = 140

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function clamp01(t: number): number
	return math.clamp(t, 0, 1)
end

local function quadOut(t: number): number
	return 1 - (1 - t) * (1 - t)
end

local function quadInOut(t: number): number
	return if t < 0.5 then 2 * t * t else 1 - (-2 * t + 2) ^ 2 / 2
end

local function backOut(t: number): number
	local c1 = 1.70158
	local c3 = c1 + 1
	return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

local function rainbowAt(t: number): Color3
	return Color3.fromHSV(t % 1, 0.5, 1)
end

-- A point on the quadratic arc from `a` to `b` that rises `lift` pixels above their middle.
local function arc(a: Vector2, b: Vector2, lift: number, t: number): Vector2
	local mid = (a + b) / 2 - Vector2.new(0, lift)
	local u = 1 - t
	return a * (u * u) + mid * (2 * u * t) + b * (t * t)
end

local function iconOf(kind: string): string
	if kind == SECRET then
		return R.Secret.Icon
	end
	local row = LuckyBlocks.kind(kind)
	return if row and row.Icon then row.Icon else ""
end

-- A tier's look, or a block kind's own (the Mystery block's), else its start tier's (Lucky 8
-- and the Gift: Uncommon's; the Sky block: Standard's).
local function look(kind: string): any
	local row = LuckyBlocks.kind(kind)
	return TIERS[kind] or (row and row.Climb and TIERS[row.Climb]) or TIERS.Standard
end

-- The Secret's silhouette tint on a picture of `kind` (white: none), and its red "?" over it.
local function tintOf(kind: string): Color3
	return if kind == SECRET then rgb(R.Secret.Tint) else Color3.new(1, 1, 1)
end

local function secretMark(parent: GuiObject, z: number): TextLabel
	local mark = HudParts.text(parent, "SecretMark", 18, W.SecretMark, rgb(R.Secret.MarkColor))
	mark.AutoLocalize = false
	mark.AnchorPoint = Vector2.new(0.5, 0.5)
	mark.Position = UDim2.fromScale(0.5, 0.52)
	mark.Size = UDim2.fromScale(R.Secret.MarkShare, R.Secret.MarkShare)
	mark.TextScaled = true
	mark.ZIndex = z
	mark.Visible = false
	return mark
end

local function hint(done: boolean): string
	if ReelFx.gamepad() then
		return if done then W.CollectPad else W.TapPad
	elseif ReelFx.touch() then
		return if done then W.Collect else W.Tap
	end
	return if done then W.CollectMouse else W.TapMouse
end

-- The screen shake's offset at `since` seconds after the impact: smooth noise on each axis,
-- fading out (1 at full strength, 0 when done), or nil once it is over.
local function shakeNoise(since: number, axis: number): number?
	local S = R.Shake
	if since >= S.Seconds then
		return nil
	end
	local fade = (1 - since / S.Seconds) ^ 2
	return fade * math.clamp(math.noise(since * S.Frequency, axis * 7.3, 0.5) * 2, -1, 1)
end

type Particle = {
	object: ImageLabel,
	mode: string,
	x: number,
	y: number,
	vx: number,
	vy: number,
	age: number,
	life: number,
	size: number,
	spin: number,
	angle: number,
	radius: number,
	turn: number,
	rainbow: boolean,
	hue: number,
	drag: number,
	gravity: number,
}

type Dot = {
	frame: Frame,
	fill: Frame,
	gloss: ImageLabel,
	mark: TextLabel,
	scale: UIScale,
	halo: ImageLabel,
}

-- One tier on the ladder: its block, its name, the node on the line before it (none for the
-- first).
type Step = {
	kind: string,
	icon: ImageLabel,
	name: TextLabel,
	node: Frame?,
}

-- Where everything goes for a screen this size (Reveal.geometry), in pixels.
type Geo = {
	size: Vector2,
	side: number,
	centre: Vector2,
	gap: number,
	pillY: number,
	pillH: number,
	pillText: number,
	titleY: number,
	titleH: number,
	dot: number,
	dotsY: number,
	tapY: number,
	tapH: number,
	ladderTop: number,
	ladderH: number,
	ladderW: number,
	block: number,
	blockCy: number,
	nameCy: number,
	nameText: number,
	arrowH: number,
}

export type Deps = {
	-- Asks the server to climb block `id` (BlockRequest "Reveal"): { ok, path, kind?, secret?,
	-- cue?, rarity? } or a refusal { ok = false, reason }.
	request: (id: number) -> any,
	-- Where the block's hotbar slot is now (absolute pixels, top bar inset included in the
	-- hotbar's own space) and its size, or nil when the bar is hidden.
	slotOf: (id: number) -> (Vector2?, number?),
	-- The hotbar slot shows nothing while the block is out of it (true), or its block again.
	mask: (id: number, on: boolean) -> (),
	-- The block landed back in its slot, now a `kind` block.
	landed: (id: number, kind: string) -> (),
	-- The climb reached the Secret (the answer: its cue and rarity): the screen is gone, the
	-- Secret's pull plays.
	secret: (reply: any) -> (),
	-- A refusal's words over the hotbar.
	refused: (reply: any) -> (),
}

local Reveal = {}
Reveal.__index = Reveal

function Reveal.new(parent: Instance, deps: Deps): any
	local self: any = setmetatable({}, Reveal)
	self.parent = parent
	self.deps = deps
	self.open = false
	self.phase = "Closed"
	return self
end

--- Whether the screen holds the player's attention (the hotbar and the HUD hide meanwhile).
--- False from the moment the block jumps back, so the hotbar is there to catch it.
function Reveal.isOpen(self: any): boolean
	return self.open and self.phase ~= "Leave"
end

--- Whether the screen is up at all (the jump back included).
function Reveal.isBusy(self: any): boolean
	return self.open
end

---------------------------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------------------------

function Reveal.build(self: any)
	local gui = Instance.new("ScreenGui")
	gui.Name = "MysteryReveal"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = R.DisplayOrder
	gui.Parent = self.parent
	self.gui = gui

	local wash = HudParts.frame(gui, "Wash")
	wash.Size = UDim2.fromScale(1, 1)
	wash.BackgroundTransparency = 1
	wash.BackgroundColor3 = rgb(look(self.kind).Glow)
	wash.ZIndex = 1
	self.wash = wash

	-- The whole screen takes the presses (touch and mouse).
	local tap = Instance.new("TextButton")
	tap.Name = "Tap"
	tap.Text = ""
	tap.AutoButtonColor = false
	tap.BackgroundTransparency = 1
	tap.Selectable = false
	tap.Size = UDim2.fromScale(1, 1)
	tap.ZIndex = 20 -- see-through, over everything
	tap.Parent = gui
	tap.Activated:Connect(function()
		self:tap()
	end)

	-- Everything that jolts with the impact's screen shake.
	local root = HudParts.frame(gui, "Root")
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = 3
	self.root = root

	-- The impact's white flash over the whole screen.
	local flash = HudParts.frame(gui, "Flash")
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1
	flash.ZIndex = 15
	self.flash = flash

	local function image(name: string, key: string, z: number): ImageLabel
		local label = Instance.new("ImageLabel")
		label.Name = name
		label.BackgroundTransparency = 1
		label.Image = IMAGES[key]
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.ZIndex = z
		label.Parent = root
		return label
	end
	self.rays = image("Rays", "Rays", 3)
	self.rays.ImageTransparency = 1
	self.glow = image("Glow", "Glow", 4)
	self.glow.ImageTransparency = 1

	local back = HudParts.frame(root, "ParticlesBack")
	back.Size = UDim2.fromScale(1, 1)
	back.ZIndex = 5
	self.back = back
	local front = HudParts.frame(root, "ParticlesFront")
	front.Size = UDim2.fromScale(1, 1)
	front.ZIndex = 9
	self.front = front

	-- Placed and sized by whole pixels every frame (step); the fractions move the picture
	-- inside it, so it never steps.
	local holder = HudParts.frame(root, "Block")
	holder.ZIndex = 7
	self.holder = holder
	local pic = Instance.new("ImageLabel")
	pic.Name = "Picture"
	pic.BackgroundTransparency = 1
	pic.ScaleType = Enum.ScaleType.Stretch
	-- A window inside the picture's clear border, moved by the leftover fraction of a pixel.
	pic.ImageRectSize = Vector2.new(R.IconPx - 2 * R.IconBorder, R.IconPx - 2 * R.IconBorder)
	pic.ImageRectOffset = Vector2.new(R.IconBorder, R.IconBorder)
	pic.AnchorPoint = Vector2.new(0.5, 0.5)
	pic.Position = UDim2.fromScale(0.5, 0.5)
	pic.Size = UDim2.fromScale(1, 1)
	pic.ZIndex = 8
	pic.Parent = holder
	self.pic = pic
	self.picMark = secretMark(holder, 9)

	local title = HudParts.text(root, "Title", 60, "")
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.TextWrapped = false
	title.Rotation = R.TitleTurnDegrees
	title.ZIndex = 10
	title.Visible = false
	self.title = title

	-- The white pill at the top: the block's name and the presses made.
	local pill = HudParts.pill(root, "Count")
	pill.AnchorPoint = Vector2.new(0.5, 0.5)
	pill.ZIndex = 10
	pill.Visible = false
	local count = HudParts.note(pill, "Words", 18, "")
	count.AutoLocalize = false -- Strings' words with numbers
	count.TextWrapped = false
	count.Size = UDim2.fromScale(1, 1)
	count.ZIndex = 11
	self.pill, self.count = pill, count
	self:buildLadder(root)

	local row = HudParts.frame(root, "Dots")
	row.AnchorPoint = Vector2.new(0.5, 0.5)
	row.ZIndex = 10
	self.row = row
	self.dots = {} :: { Dot }
	for i = 1, CLICKS do
		local frame = HudParts.frame(row, "Dot" .. i)
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.BackgroundTransparency = 0.15
		frame.BackgroundColor3 = HudParts.tone("Ink")
		frame.ZIndex = 11
		frame.Visible = false
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0.5, 0)
		round.Parent = frame
		local edge = Instance.new("UIStroke")
		edge.Name = "Edge"
		edge.Color = HudParts.tone("Ink")
		edge.Thickness = R.DotOutlinePx
		edge.Parent = frame
		-- A soft glow behind the next dot, pulsing (a glow pulses smoothly; a size would step).
		local halo = Instance.new("ImageLabel")
		halo.Name = "Halo"
		halo.BackgroundTransparency = 1
		halo.Image = IMAGES.Glow
		halo.AnchorPoint = Vector2.new(0.5, 0.5)
		halo.Position = UDim2.fromScale(0.5, 0.5)
		halo.Size = UDim2.fromScale(R.DotPulse.HaloShare, R.DotPulse.HaloShare)
		halo.ImageTransparency = 1
		halo.ZIndex = 10
		halo.Parent = frame
		local fill = HudParts.frame(frame, "Fill")
		fill.AnchorPoint = Vector2.new(0.5, 0.5)
		fill.Position = UDim2.fromScale(0.5, 0.5)
		fill.Size = UDim2.fromScale(1, 1)
		fill.BackgroundTransparency = 1
		fill.ZIndex = 12
		local fillRound = Instance.new("UICorner")
		fillRound.CornerRadius = UDim.new(0.5, 0)
		fillRound.Parent = fill
		local gloss = Instance.new("ImageLabel")
		gloss.Name = "Gloss"
		gloss.BackgroundTransparency = 1
		gloss.Image = IMAGES.Gloss
		gloss.Size = UDim2.fromScale(1, 1)
		gloss.ImageTransparency = 1
		gloss.ZIndex = 13
		gloss.Parent = frame
		local mark = HudParts.text(frame, "Mark", 18, "?")
		mark.AutoLocalize = false
		mark.AnchorPoint = Vector2.new(0.5, 0.5)
		mark.Position = UDim2.fromScale(0.5, 0.5)
		mark.Size = UDim2.fromScale(0.8, 0.8)
		mark.ZIndex = 14
		mark.Visible = false
		table.insert(self.dots, {
			frame = frame,
			fill = fill,
			gloss = gloss,
			mark = mark,
			scale = UIAnim.scaleOf(frame),
			halo = halo,
		})
	end

	-- The white Tap! button with the pointer hand (a press anywhere counts; it says what to do).
	local tapButton = HudParts.candy(root, "", function()
		self:tap()
	end, "White", "Hand")
	tapButton.Name = "Hint"
	tapButton.Selectable = false
	tapButton.AnchorPoint = Vector2.new(0.5, 0.5)
	tapButton.ZIndex = 10
	tapButton.Visible = false
	local parts = HudParts.candyParts(tapButton)
	if parts then
		parts.icon.Image = R.TapIcon
	end
	HudParts.setIconShare(tapButton, R.TapIconShare)
	self.hint = tapButton

	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:layout()
	end)
end

-- The screen's size in pixels. Studio QA: a MysteryPreviewSize attribute (Vector2) on the
-- PlayerGui, set before the block is opened, lays the screen out in a box that size at the top
-- left, standing in for a phone (as UltScreen's PreviewSize).
function Reveal.screenSize(self: any): Vector2
	local preview = if RunService:IsStudio()
		then self.parent:GetAttribute("MysteryPreviewSize")
		else nil
	return if typeof(preview) == "Vector2" then preview else self.gui.AbsoluteSize
end

-- The ladder along the bottom: the dark line through every tier, the filled line over it up
-- to the tier on show, each tier's block with its name, a round node halfway between two, and
-- the arrow over the tier on show.
function Reveal.buildLadder(self: any, root: Frame)
	local ladder = HudParts.frame(root, "Ladder")
	ladder.ZIndex = 10
	ladder.Visible = false
	self.ladder = ladder
	local function bar(name: string, colour: Color3, z: number): Frame
		local line = HudParts.frame(ladder, name)
		line.AnchorPoint = Vector2.new(0, 0.5)
		line.BackgroundTransparency = 0
		line.BackgroundColor3 = colour
		line.ZIndex = z
		HudParts.corner(line, 999)
		return line
	end
	self.lineOff = bar("LineOff", rgb(LD.LineOff), 10)
	local edge = Instance.new("UIStroke")
	edge.Color = HudParts.tone("Ink")
	edge.Thickness = 2
	edge.Parent = self.lineOff
	self.lineOn = bar("LineOn", Color3.new(1, 1, 1), 11)
	self.steps = {} :: { Step }
	for i, kind in ORDER do
		local node: Frame? = nil
		if i > 1 then
			local made = HudParts.frame(ladder, "Node" .. i)
			made.AnchorPoint = Vector2.new(0.5, 0.5)
			made.BackgroundTransparency = 0
			made.BackgroundColor3 = rgb(LD.NodeOff)
			made.ZIndex = 12
			HudParts.corner(made, 999)
			local ring = Instance.new("UIStroke")
			ring.Color = HudParts.tone("Ink")
			ring.Thickness = 2
			ring.Parent = made
			node = made
		end
		local icon = Instance.new("ImageLabel")
		icon.Name = "Block" .. i
		icon.BackgroundTransparency = 1
		icon.Image = iconOf(kind)
		icon.ScaleType = Enum.ScaleType.Fit
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.ImageColor3 = tintOf(kind)
		icon.ZIndex = 13
		icon.Parent = ladder
		if kind == SECRET then
			self.rungMark = secretMark(icon, 14)
			self.rungMark.Visible = true
		end
		local name = HudParts.text(ladder, "Name" .. i, 14, SHORT[kind] or kind)
		name.AnchorPoint = Vector2.new(0.5, 0.5)
		name.TextWrapped = false
		name.ZIndex = 13
		table.insert(self.steps, { kind = kind, icon = icon, name = name, node = node })
	end
	local arrow = HudParts.icon(ladder, "ChevronUp", "Arrow")
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.ZIndex = 14
	self.arrow = arrow
	self.lit = 0 -- the ladder's tier on show (0: none yet)
end

-- Everything's place for the screen's size: the top stack (the pill, the two lines, the name),
-- the bottom stack (the ladder, the Tap! button, the dots) and the block in the room between.
function Reveal.geometry(self: any): Geo
	local size = self:screenSize()
	local H, Wd = size.Y, size.X
	local gap = math.max(4, H * R.GapShare)
	local minText = R.MinTextPx
	local P = R.Pill
	local pillH = math.max(minText / P.TextShare, H * P.HeightShare)
	local pillY = H * P.Y
	-- The ladder from the bottom up: the names, the blocks (the lit one raised), the arrow.
	local block = H * LD.BlockShare
	local litSide = block * LD.LitScale
	local raise = block * LD.RaiseShare
	local arrowH = block * LD.ArrowShare
	local nameText = math.clamp(H * LD.NameTextShare, minText, LD.NameMaxTextPx)
	local blockCy = arrowH + 2 + raise + litSide / 2
	local nameCy = blockCy + block / 2 + 2 + nameText / 2
	local ladderH = nameCy + nameText / 2 + 2
	local ladderTop = H * (1 - LD.BottomShare) - ladderH
	local ladderW = math.min(H * LD.WidthShare, Wd * LD.MaxWidthShare)
	-- Over it the Tap! button, then the dots.
	local planned = math.min(H * R.BlockShare, Wd * R.BlockMaxShareOfWidth)
	local tapH = math.max(R.TapMinPx, H * R.TapHeightShare)
	local tapY = ladderTop - gap - tapH / 2
	local dot = math.max(10, planned * R.DotShare)
	local dotsY = tapY - tapH / 2 - gap - dot / 2
	-- The name under the pill, the block in the room between it and the dots (with room for
	-- its float).
	local titleH = planned * R.TitleHeightShare
	local titleTop = pillY + pillH / 2 + gap
	local blockTop = titleTop + titleH + gap / 2
	local blockBottom = dotsY - dot / 2 - gap - planned * R.Float.HeightShare
	local side = math.max(40, math.min(planned, blockBottom - blockTop))
	return {
		size = size,
		side = side,
		centre = Vector2.new(Wd / 2, (blockTop + blockBottom) / 2),
		gap = gap,
		pillY = pillY,
		pillH = pillH,
		pillText = math.max(minText, pillH * P.TextShare),
		titleY = titleTop + titleH / 2,
		titleH = titleH,
		dot = dot,
		dotsY = dotsY,
		tapY = tapY,
		tapH = tapH,
		ladderTop = ladderTop,
		ladderH = ladderH,
		ladderW = ladderW,
		block = block,
		blockCy = blockCy,
		nameCy = nameCy,
		nameText = nameText,
		arrowH = arrowH,
	}
end

-- The block's side, its resting middle and the screen's size, in pixels.
function Reveal.metrics(self: any): (number, Vector2, Vector2)
	local g = self:geometry()
	return g.side, g.centre, g.size
end

function Reveal.layout(self: any)
	if self.gui == nil then
		return
	end
	local g = self:geometry()
	local side, centre, size = g.side, g.centre, g.size
	self.side, self.centre = side, centre
	self.root.Size = if size == self.gui.AbsoluteSize
		then UDim2.fromScale(1, 1)
		else UDim2.fromOffset(size.X, size.Y)
	self.holder.Size = UDim2.fromOffset(side, side)
	HudParts.setTextSize(self.picMark, side * R.Secret.MarkShare)
	self.glow.Size = UDim2.fromOffset(side * R.GlowShare, side * R.GlowShare)
	self.glow.Position = UDim2.fromOffset(centre.X, centre.Y)
	self.rays.Size = UDim2.fromOffset(side * R.RaysShare, side * R.RaysShare)
	self.rays.Position = UDim2.fromOffset(centre.X, centre.Y)
	-- The top: the pill, the tier's name.
	HudParts.setTextSize(self.count, g.pillText)
	local countW =
		TextService:GetTextSize(self.count.Text, g.pillText, FONT, Vector2.new(4000, 400)).X
	self.pill.Size =
		UDim2.fromOffset(math.min(size.X * 0.9, countW + 2 * g.pillH * R.Pill.PadShare), g.pillH)
	self.pill.Position = UDim2.fromOffset(size.X / 2, g.pillY)
	self.title.Size = UDim2.fromOffset(math.min(size.X * 0.94, side * R.TitleWidthShare), g.titleH)
	self.title.Position = UDim2.fromOffset(size.X / 2, g.titleY)
	HudParts.setTextSize(self.title, g.titleH)
	-- Under the block: the dots, the Tap! button.
	local dot = g.dot
	local gap = dot * R.DotGapShare / R.DotShare
	local rowW = CLICKS * dot + (CLICKS - 1) * gap
	self.row.Size = UDim2.fromOffset(rowW, dot)
	self.row.Position = UDim2.fromOffset(size.X / 2, g.dotsY)
	for i, d in self.dots do
		d.frame.Size = UDim2.fromOffset(dot, dot)
		d.frame.Position = UDim2.fromOffset((i - 1) * (dot + gap) + dot / 2, dot / 2)
		HudParts.setTextSize(d.mark, dot * 0.7)
	end
	local hintText = math.max(R.MinTextPx, math.floor(g.tapH * 0.5))
	HudParts.setButtonTextSize(self.hint, hintText)
	local hintW = HudParts.candyWidth(self.hint, g.tapH, hintText)
	self.hint.Size = UDim2.fromOffset(math.ceil(hintW + g.tapH * 0.4), g.tapH)
	self.hint.Position = UDim2.fromOffset(size.X / 2, g.tapY)
	self:layoutLadder(g)
end

-- The ladder `g.ladderW` wide, centred along the bottom: the dark line through every tier, the
-- filled one up to the tier on show, the nodes halfway, the blocks (the lit one bigger and
-- raised, the ones ahead a little faded), their names, the arrow over the lit one.
function Reveal.layoutLadder(self: any, g: Geo)
	local size = g.size
	local ladder: Frame = self.ladder
	ladder.Position = UDim2.fromOffset(0, g.ladderTop)
	ladder.Size = UDim2.fromOffset(size.X, g.ladderH)
	local n = #self.steps
	local left = (size.X - g.ladderW) / 2
	local spacing = g.ladderW / math.max(1, n - 1)
	local block = g.block
	local lineH = math.max(3, block * LD.LineShare)
	local function xOf(i: number): number
		return left + (i - 1) * spacing
	end
	self.lineOff.Position = UDim2.fromOffset(xOf(1), g.blockCy)
	self.lineOff.Size = UDim2.fromOffset(g.ladderW, lineH)
	local lit = math.max(1, self.lit)
	self.lineOn.Position = UDim2.fromOffset(xOf(1), g.blockCy)
	self.lineOn.Size = UDim2.fromOffset(math.max(lineH, (lit - 1) * spacing), lineH)
	self.lineOn.Visible = self.lit > 1
	local nodePx = math.max(6, block * LD.NodeShare)
	for i, step: Step in self.steps do
		local on = i == self.lit
		local scale = if on then LD.LitScale else 1
		local raise = if on then block * LD.RaiseShare else 0
		step.icon.Size = UDim2.fromOffset(block * scale, block * scale)
		step.icon.Position = UDim2.fromOffset(xOf(i), g.blockCy - raise)
		step.icon.ImageTransparency = if self.lit > 0 and i > self.lit
			then LD.FadeTransparency
			else 0
		if step.kind == SECRET and self.rungMark then
			HudParts.setTextSize(self.rungMark, block * scale * R.Secret.MarkShare)
		end
		HudParts.setTextSize(step.name, g.nameText)
		step.name.Size = UDim2.fromOffset(spacing * 0.98, g.nameText + 4)
		step.name.Position = UDim2.fromOffset(xOf(i), g.nameCy)
		local node = step.node
		if node then
			node.Size = UDim2.fromOffset(nodePx, nodePx)
			node.Position = UDim2.fromOffset((xOf(i - 1) + xOf(i)) / 2, g.blockCy)
			node.BackgroundColor3 = if i <= self.lit
				then self.lineOn.BackgroundColor3
				else rgb(LD.NodeOff)
		end
	end
	local arrowPx = g.arrowH
	self.arrow.Size = UDim2.fromOffset(arrowPx, arrowPx)
	self.arrow.Position = UDim2.fromOffset(xOf(lit), arrowPx / 2)
	self.arrow.Visible = self.lit > 0
end

---------------------------------------------------------------------------------------------
-- Particles (one list for the whole screen, stepped every frame)
---------------------------------------------------------------------------------------------

function Reveal.spawn(self: any, layer: Frame, emitter: any, mode: string): Particle?
	if #self.particles >= MAX_PARTICLES then
		return nil
	end
	local random: Random = self.random
	local side = self.side
	local label = Instance.new("ImageLabel")
	label.Name = "P"
	label.BackgroundTransparency = 1
	label.Image = IMAGES[emitter.Image] or IMAGES.Spark
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.ImageTransparency = 1
	label.ZIndex = layer.ZIndex
	local rainbow = emitter.Rainbow == true
	if not rainbow then
		local colours = emitter.Colors or { { 255, 255, 255 } }
		label.ImageColor3 = rgb(colours[random:NextInteger(1, #colours)])
	end
	local size = side * random:NextNumber(emitter.Size[1], emitter.Size[2])
	local speed = if emitter.Speed then random:NextNumber(emitter.Speed[1], emitter.Speed[2]) else 0
	local p: Particle = {
		object = label,
		mode = mode,
		x = 0,
		y = 0,
		vx = 0,
		vy = 0,
		age = 0,
		life = random:NextNumber(emitter.Life[1], emitter.Life[2]),
		size = size,
		spin = (emitter.Spin or 0) * (if random:NextNumber() < 0.5 then -1 else 1),
		angle = random:NextNumber(0, 360),
		radius = 0,
		turn = 0,
		rainbow = rainbow,
		hue = random:NextNumber(),
		drag = 0,
		gravity = 0,
	}
	if mode == "Rise" then
		p.x = side * random:NextNumber(-0.65, 0.65)
		p.y = side * random:NextNumber(0.25, 0.6)
		p.vy = -speed * side
		p.vx = side * random:NextNumber(-0.05, 0.05)
	elseif mode == "Twinkle" then
		local a = random:NextNumber(0, 2 * math.pi)
		local r = side * random:NextNumber(0.42, 0.85)
		p.x, p.y = math.cos(a) * r, math.sin(a) * r * 0.85
	elseif mode == "Orbit" then
		p.radius = side * random:NextNumber(0.6, 0.72)
		p.turn = random:NextNumber(0, 2 * math.pi)
		p.vx = speed * 2 * math.pi -- radians a second
	elseif mode == "Fountain" then
		p.x = side * random:NextNumber(-0.15, 0.15)
		p.y = -side * 0.15
		p.vx = side * random:NextNumber(-0.7, 0.7)
		p.vy = -speed * side
		p.gravity = side * 2.4
	elseif mode == "Burst" then
		local a = random:NextNumber(0, 2 * math.pi)
		p.x, p.y = math.cos(a) * side * 0.25, math.sin(a) * side * 0.25
		p.vx, p.vy = math.cos(a) * speed * side, math.sin(a) * speed * side
		p.angle = math.deg(a)
		p.drag = 2.5
	end
	label.Size = UDim2.fromOffset(size, if emitter.Image == "Streak" then size * 0.25 else size)
	label.Parent = layer
	table.insert(self.particles, p)
	return p
end

-- A burst on landing: sparks flying out of the block, a ring and a white flash.
function Reveal.burst(self: any, kind: string)
	local B = R.Burst
	local tier = look(kind)
	local random: Random = self.random
	local n = math.max(4, math.floor(B.Sparks * Quality.rate() + 0.5))
	for _ = 1, n do
		local p = self:spawn(self.front, {
			Image = "Spark",
			Colors = { tier.Glow, { 255, 255, 255 } },
			Rainbow = tier.Rainbow,
			Size = { 0.06, 0.12 },
			Life = B.Life,
			Spin = 240,
		}, "Spark")
		if p then
			local a = random:NextNumber(0, 2 * math.pi)
			local speed = self.side * random:NextNumber(B.SpeedShare[1], B.SpeedShare[2])
			p.vx, p.vy = math.cos(a) * speed, math.sin(a) * speed
			p.drag = 3
			p.gravity = self.side * 0.8
		end
	end
	local centre = self.centre
	local ring = Instance.new("ImageLabel")
	ring.Name = "Ring"
	ring.BackgroundTransparency = 1
	ring.Image = IMAGES.Ring
	ring.ImageColor3 = rgb(tier.Glow)
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromOffset(centre.X, centre.Y)
	ring.Size = UDim2.fromOffset(self.side * 0.6, self.side * 0.6)
	ring.ZIndex = 6
	ring.Parent = self.root
	local reach = self.side * B.RingShare
	local tween = TweenService:Create(
		ring,
		TweenInfo.new(B.RingSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(reach, reach), ImageTransparency = 1 }
	)
	tween.Completed:Connect(function()
		ring:Destroy()
	end)
	tween:Play()
	UIAnim.glowBurst(self.holder, Color3.new(1, 1, 1), 1.4)
end

function Reveal.stepParticles(self: any, dt: number, clock: number)
	-- New ones from the tier's emitters (Lower effects: fewer; Reduce Motion: only twinkles).
	local tier = look(self.shown)
	local rate = Quality.rate()
	local reduced = UIAnim.reduced()
	if self.phase ~= "Leave" and self.phase ~= "Arrive" then
		self.carry = self.carry or {}
		for i, emitter in tier.Particles do
			local mode = emitter.Mode
			if not reduced or mode == "Twinkle" then
				local key = self.shown .. i
				local due = (self.carry[key] or 0) + emitter.Rate * rate * dt
				while due >= 1 do
					due -= 1
					local layer = if mode == "Twinkle" or mode == "Orbit"
						then self.front
						else self.back
					self:spawn(layer, emitter, mode)
				end
				self.carry[key] = due
			end
		end
	end
	local centre = self.centre
	for i = #self.particles, 1, -1 do
		local p = self.particles[i]
		p.age += dt
		local t = p.age / p.life
		if t >= 1 or p.object.Parent == nil then
			p.object:Destroy()
			table.remove(self.particles, i)
		else
			local alpha: number
			local scale = 1
			if p.mode == "Twinkle" then
				scale = math.sin(math.pi * t)
				alpha = 0
			elseif p.mode == "Orbit" then
				p.turn += p.vx * dt
				p.x = math.cos(p.turn) * p.radius
				p.y = math.sin(p.turn) * p.radius * 0.32
				-- Behind the block on the far side of the ring.
				local layer = if math.sin(p.turn) < 0 then self.back else self.front
				if p.object.Parent ~= layer then
					p.object.Parent = layer
				end
				alpha = if t < 0.15 then 1 - t / 0.15 elseif t > 0.7 then (t - 0.7) / 0.3 else 0
			else
				if p.drag > 0 then
					local k = math.exp(-p.drag * dt)
					p.vx *= k
					p.vy *= k
				end
				p.vy += p.gravity * dt
				p.x += p.vx * dt
				p.y += p.vy * dt
				if p.mode == "Rise" then
					p.x += math.sin(clock * 2 + p.hue * 6) * self.side * 0.02 * dt
				end
				alpha = if t < 0.15 then 1 - t / 0.15 elseif t > 0.55 then (t - 0.55) / 0.45 else 0
			end
			p.angle += p.spin * dt
			local object = p.object
			object.Position = UDim2.fromOffset(centre.X + p.x, centre.Y + p.y)
			object.Rotation = p.angle
			object.ImageTransparency = alpha
			if p.mode == "Twinkle" or p.mode == "Spark" then
				local s = p.size * (if p.mode == "Spark" then 1 - t * 0.6 else scale)
				object.Size = UDim2.fromOffset(s, s)
			end
			if p.rainbow then
				object.ImageColor3 = rainbowAt(p.hue + clock * 0.4)
			end
		end
	end
end

---------------------------------------------------------------------------------------------
-- The tier on show
---------------------------------------------------------------------------------------------

-- The name over the block ("EPIC!"; "STANDARD" plain, and the arriving block's own name before
-- the first press: "MYSTERY", "RARE", "LUCKY 8"), its colour (or the rainbow) and the glow, rays
-- and wash behind it; the ladder lights the tier (a block that is not a tier: nothing yet).
function Reveal.showTier(self: any, kind: string, slam: boolean, arriving: boolean?)
	self.shown = kind
	local tier = look(kind)
	self.pic.Image = iconOf(kind)
	self.pic.ImageColor3 = tintOf(kind)
	self.picMark.Visible = kind == SECRET
	local words = if kind == "Mystery"
		then W.Title
		else (W.Tiers[kind] or KIND_TITLES[kind] or string.upper(kind))
	self.title.Text = if arriving or kind == "Standard" then words else W.Exclaim:format(words)
	self:lightStep(kind)
	-- A rainbow name is white under its gradient (a colour under it would darken it).
	self.title.TextColor3 = if tier.Rainbow then Color3.new(1, 1, 1) else rgb(tier.Color)
	if self.rainbow then
		self.rainbow.stop()
		self.rainbow = nil
	end
	if tier.Rainbow then
		self.rainbow = UIAnim.rainbow(self.title)
	end
	if slam then
		UIAnim.slam(self.title, rgb(tier.Glow))
	end
	local info = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(self.glow, info, { ImageColor3 = rgb(tier.Glow) }):Play()
	TweenService:Create(self.rays, info, { ImageColor3 = rgb(tier.Glow) }):Play()
	TweenService:Create(self.wash, info, { BackgroundColor3 = rgb(tier.Glow) }):Play()
end

-- The ladder's tier `kind` lit: the filled line grows to it (in its colour), it rises with the
-- arrow over it, the ones ahead fade a little. Not a ladder tier (the Mystery block in flight):
-- nothing lit.
function Reveal.lightStep(self: any, kind: string)
	local index = table.find(ORDER, kind) or 0
	local before = self.lit or 0
	self.lit = index
	if self.ladder == nil then
		return
	end
	local glow = rgb(look(kind).Glow)
	self.lineOn.BackgroundColor3 = glow
	self.arrow.ImageColor3 = glow
	local g = self:geometry()
	if index > before and before > 0 and not UIAnim.reduced() then
		-- The filled line grows from the tier it was on to the new one.
		local spacing = g.ladderW / math.max(1, #self.steps - 1)
		local lineH = math.max(3, g.block * LD.LineShare)
		self:layoutLadder(g)
		self.lineOn.Size = UDim2.fromOffset(math.max(lineH, (before - 1) * spacing), lineH)
		self.lineOn.Visible = true
		TweenService:Create(
			self.lineOn,
			TweenInfo.new(LD.GrowSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = UDim2.fromOffset(math.max(lineH, (index - 1) * spacing), lineH) }
		):Play()
	else
		self:layoutLadder(g)
	end
	local step: Step? = self.steps[index]
	if step and self.ladder.Visible and not UIAnim.reduced() then
		UIAnim.bounce(step.icon)
		UIAnim.bounce(self.arrow)
	end
end

-- The pill's count: the block's name, the presses made of the four.
function Reveal.setCount(self: any, presses: number)
	self.count.Text = W.Count:format(NAMES[self.kind] or self.kind, presses, CLICKS)
	if self.gui then
		self:layout()
	end
end

-- Dot `i` fills in the colour of the tier its press showed; the next one asks "?".
function Reveal.fillDot(self: any, i: number, kind: string)
	local d: Dot? = self.dots[i]
	if d then
		local tier = look(kind)
		d.mark.Visible = false
		d.fill.BackgroundTransparency = 0
		local gradient = d.fill:FindFirstChild("Rainbow")
		if tier.Rainbow then
			-- A rainbow tier's dot keeps the rainbow.
			d.fill.BackgroundColor3 = Color3.new(1, 1, 1)
		else
			d.fill.BackgroundColor3 = rgb(tier.Glow)
			if gradient then
				gradient:Destroy()
			end
		end
		d.gloss.ImageTransparency = 0.1
		if self.dotPulse then
			self.dotPulse.stop()
			self.dotPulse = nil
		end
		d.scale.Scale = 1.35
		TweenService:Create(
			d.scale,
			TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }
		):Play()
	end
	self:setCount(i)
	self:markNext(i + 1)
end

function Reveal.markNext(self: any, i: number)
	local d: Dot? = self.dots[i]
	if d == nil then
		return
	end
	d.mark.Visible = true
	d.fill.BackgroundTransparency = 0
	d.fill.BackgroundColor3 = Color3.new(1, 1, 1)
	if d.fill:FindFirstChild("Rainbow") == nil then
		local gradient = Instance.new("UIGradient")
		gradient.Name = "Rainbow"
		gradient.Rotation = 45
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 120, 160)),
			ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 220, 110)),
			ColorSequenceKeypoint.new(0.65, Color3.fromRGB(110, 230, 160)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 160, 255)),
		})
		gradient.Parent = d.fill
	end
	d.gloss.ImageTransparency = 0.1
	if self.dotPulse then
		self.dotPulse.stop()
	end
	local P = R.DotPulse
	local halo = d.halo
	local handle = UIAnim.loop(d.frame, function(clock)
		local wave = 0.5 + 0.5 * math.sin(2 * math.pi * clock / P.Seconds)
		halo.ImageTransparency = lerp(P.Transparency[2], P.Transparency[1], wave)
	end)
	self.dotPulse = {
		stop = function()
			handle.stop()
			halo.ImageTransparency = 1
		end,
	}
end

---------------------------------------------------------------------------------------------
-- Open, press, collect
---------------------------------------------------------------------------------------------

-- Every other screen of ours hides while this one is up (the hotbar by Progression, through
-- isOpen, so it can come back to catch the block).
function Reveal.hideOthers(self: any)
	local hidden = {}
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		for _, gui in playerGui:GetChildren() do
			if
				gui:IsA("ScreenGui")
				and gui.Enabled
				and gui ~= self.gui
				and gui.Name ~= "LuckyHotbar"
				and gui.Name ~= "Freecam"
			then
				gui.Enabled = false
				table.insert(hidden, gui)
			end
		end
	end
	self.hidden = hidden
end

function Reveal.showOthers(self: any)
	local hidden = self.hidden
	self.hidden = nil
	for _, gui in hidden or {} do
		if gui.Parent then
			gui.Enabled = true
		end
	end
end

--- Opens the screen for the ready unclimbed `kind` block `id` (nil: a Mystery block): it jumps
--- out of the hotbar slot at `from` (absolute pixels in the hotbar's space, and the slot's
--- size) while the server climbs it. `fake` (Studio tests only, GuiQA "mystery"): a made-up
--- reply, nothing asked.
function Reveal.play(
	self: any,
	id: number,
	from: Vector2?,
	fromPx: number?,
	fake: any?,
	kind: string?
)
	if self.open then
		return
	end
	self.open = true
	self.id = id
	self.kind = kind or "Mystery"
	self.reply = nil
	self.failed = false
	UISound.play("MysteryOpen")
	self.presses = 0
	self.particles = {}
	self.carry = {}
	self.random = Random.new()
	self.buffered = 0
	self.anim = nil
	self.clock = 0
	self.floatClock = 0
	self:build()
	self:setCount(0)
	self:hideOthers()
	ScreenBlur.set(self, true)
	self.deps.mask(id, true)
	GuiService.SelectedObject = nil
	ContextActionService:BindActionAtPriority(
		ACTION,
		function(_, state: Enum.UserInputState)
			if state == Enum.UserInputState.Begin then
				self:tap()
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.ContextActionPriority.High.Value + 10,
		Enum.KeyCode.ButtonA,
		Enum.KeyCode.ButtonR2,
		Enum.KeyCode.Space,
		Enum.KeyCode.Return
	)
	self.connection = RunService.RenderStepped:Connect(function(dt: number)
		self:step(dt)
	end)
	-- The 3D world behind the blur shakes with the impact too (a small move of the camera
	-- after Roblox's camera has placed it; a move, never a turn, so the camera never drifts).
	RunService:BindToRenderStep(SHAKE, Enum.RenderPriority.Camera.Value + 1, function()
		local camera = workspace.CurrentCamera
		local since = if self.shakeAt then self.clock - self.shakeAt else math.huge
		local nx, ny = shakeNoise(since, 4), shakeNoise(since, 5)
		if camera and nx and ny then
			local k = R.Shake.CameraStuds
			camera.CFrame = camera.CFrame * CFrame.new(nx * k, ny * k, 0)
		end
	end)
	task.spawn(function()
		local reply = if fake ~= nil then fake else self.deps.request(id)
		if not self.open or self.id ~= id then
			return
		end
		if
			type(reply) ~= "table"
			or not reply.ok
			or type(reply.path) ~= "table"
			or #reply.path ~= CLICKS
		then
			self.deps.refused(reply)
			self.failed = true
			self:leave()
			return
		end
		for _, tier in reply.path do
			if not table.find(ORDER, tier) then
				self.deps.refused({ ok = false, reason = "Error" })
				self.failed = true
				self:leave()
				return
			end
		end
		self.reply = reply
		if self.waitingReply then
			self.waitingReply = false
			self:press()
		end
	end)

	-- The jump out of the hotbar.
	local inset = GuiService:GetGuiInset()
	local side, centre, size = self:metrics()
	local start = if from
		then from + Vector2.new(0, inset.Y)
		else Vector2.new(size.X / 2, size.Y + side / 2)
	local startScale = (fromPx or side * 0.25) / side
	self:showTier(self.kind, false, true)
	self.phase = "Arrive"
	local A = R.Arrive
	local reduced = UIAnim.reduced()
	self.pose = { at = start, scale = startScale, turn = A.FromTurn, lift = 0 }
	self.anim = {
		seconds = A.Seconds,
		step = function(t: number)
			local e = backOut(t)
			if reduced then
				self.pose.at = centre
				self.pose.scale = lerp(0.8, 1, quadOut(t))
				self.pose.turn = 0
				self.pic.ImageTransparency = 1 - t
			else
				self.pose.at = arc(start, centre, size.Y * A.ArcShare, quadOut(t))
				self.pose.scale = lerp(startScale, 1, e)
				self.pose.turn = lerp(A.FromTurn, 0, quadOut(t))
			end
		end,
		done = function()
			self.pic.ImageTransparency = 0
			self.pose.at, self.pose.scale, self.pose.turn = centre, 1, 0
			self:arrived()
		end,
	}
	TweenService:Create(
		self.glow,
		TweenInfo.new(A.Seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ ImageTransparency = R.GlowTransparency }
	):Play()
	TweenService:Create(
		self.rays,
		TweenInfo.new(A.Seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ ImageTransparency = R.RaysTransparency }
	):Play()
	TweenService:Create(
		self.wash,
		TweenInfo.new(A.Seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = R.BackTransparency }
	):Play()
	task.delay(A.TitleAt, function()
		if self.open and self.phase ~= "Leave" then
			self.pill.Visible = true
			UIAnim.popIn(self.pill)
		end
	end)
	task.delay(A.DotsAt, function()
		if not self.open or self.phase == "Leave" then
			return
		end
		self.ladder.Visible = true
		UIAnim.popIn(self.ladder)
		for i, d in self.dots do
			task.delay((i - 1) * A.DotStagger, function()
				if self.open and self.phase ~= "Leave" then
					d.frame.Visible = true
					UIAnim.popIn(d.frame)
				end
			end)
		end
		self:markNext(1)
	end)
	task.delay(A.HintAt, function()
		if
			self.open
			and self.phase ~= "Leave"
			and self.phase ~= "Done"
			and not self.hint.Visible
		then
			HudParts.setText(self.hint, hint(false))
			self:layout()
			self.hint.Visible = true
			UIAnim.popIn(self.hint)
		end
	end)
end

-- Landed: still the block it was, its name slamming in over it with a soft white puff; the
-- ladder lights its tier (a tier block), or nothing until the first press shows the start.
function Reveal.arrived(self: any)
	self:showTier(self.kind, false, true)
	self.title.Visible = true
	UIAnim.slam(self.title, Color3.new(1, 1, 1))
	self:puff()
	self.phase = "Wait"
	self:afterAnim()
end

-- A press, a buffered press or the collect: whatever the screen is waiting for.
function Reveal.tap(self: any)
	if not self.open then
		return
	end
	if self.phase == "Wait" then
		self:press()
	elseif self.phase == "Done" then
		if os.clock() >= (self.collectAt or 0) then
			self:leave()
		end
	elseif self.phase == "Arrive" or self.phase == "Press" then
		-- Taps during an animation wait their turn (each one is a press).
		self.buffered = math.min((self.buffered or 0) + 1, CLICKS - self.presses)
	end
end

function Reveal.afterAnim(self: any)
	if self.phase == "Wait" and (self.buffered or 0) > 0 then
		self.buffered -= 1
		self:press()
	end
end

function Reveal.press(self: any)
	if self.reply == nil then
		self.waitingReply = true -- the server has not answered yet: this press waits for it
		self.phase = "Press"
		return
	end
	self.presses += 1
	local i = self.presses
	local tiers = self.reply.path
	-- The first press shows the start: a change from the arriving block, or a tier block that
	-- starts at its own tier keeping it.
	local before = if i == 1 then self.kind else tiers[i - 1]
	local after = tiers[i]
	self.phase = "Press"
	local side = self.side
	local reduced = UIAnim.reduced()
	if self.hint.Visible and not reduced then
		UIAnim.thump(self.hint) -- the Tap! button stays and swells with each press
	end
	local P = R.Press
	local finish = function()
		self:fillDot(i, after)
		if i >= CLICKS then
			self:done()
		else
			self.phase = "Wait"
			self:afterAnim()
		end
	end
	-- A hop: up slowing, down speeding up (an arc), a rattle on the way, and a squash first.
	local function hop(
		seconds: number,
		height: number,
		rattle: number,
		turns: number,
		stretch: number
	)
		local total = P.SquashSeconds + seconds
		return total,
			function(t: number)
				local now = t * total
				if now < P.SquashSeconds then
					self.pose.scale = lerp(1, P.Squash, quadOut(now / P.SquashSeconds))
					return
				end
				local q = clamp01((now - P.SquashSeconds) / seconds)
				local arcUp = math.sin(math.pi * q)
				self.pose.scale = lerp(P.Squash, 1, quadOut(clamp01(q * 3))) + stretch * arcUp
				if not reduced then
					self.pose.lift = side * height * arcUp
					self.pose.turn = rattle * math.sin(2 * math.pi * turns * q) * arcUp
				end
			end
	end
	if before == after then
		-- Kept: a squash, a small hop and a rattle.
		UISound.play("MysteryKeep")
		local K = R.Keep
		local total, step = hop(K.Seconds, K.HopShare, K.RattleDegrees, K.RattleTurns, 0)
		self.anim = {
			seconds = total,
			step = step,
			done = function()
				self.pose.scale, self.pose.lift, self.pose.turn = 1, 0, 0
				finish()
			end,
		}
		return
	end
	-- Changed: squash, one quick hop with a rattle, then the impact as it lands (flash,
	-- shake, burst) as the picture becomes the new block, which lands a little big and settles.
	UISound.play("MysteryUpgrade")
	local U = R.Upgrade
	local total, step = hop(U.HopSeconds, U.HopShare, U.RattleDegrees, U.RattleTurns, U.Stretch)
	self.anim = {
		seconds = total,
		step = step,
		done = function()
			self.pose.lift, self.pose.turn = 0, 0
			self.pic.Image = iconOf(after)
			self:impact()
			self:showTier(after, true)
			self:burst(after)
			self.anim = {
				seconds = U.LandSeconds,
				step = function(t: number)
					self.pose.scale = lerp(U.LandScale, 1, backOut(t))
				end,
				done = function()
					self.pose.scale = 1
					finish()
				end,
			}
		end,
	}
end

-- The impact as the block becomes the next one: a white flash over the screen and on the
-- block, and the screen shaking (none with Reduce Motion).
function Reveal.impact(self: any)
	local F = R.Flash
	local flash: Frame = self.flash
	flash.BackgroundTransparency = 1
	local flashIn = TweenService:Create(
		flash,
		TweenInfo.new(F.InSeconds, Enum.EasingStyle.Linear),
		{ BackgroundTransparency = F.Transparency }
	)
	flashIn.Completed:Connect(function()
		TweenService:Create(
			flash,
			TweenInfo.new(F.OutSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1 }
		):Play()
	end)
	flashIn:Play()
	self:puff()
	if not UIAnim.reduced() then
		self.shakeAt = self.clock
	end
end

-- A white glow bursting from the block (the impact, and the landing as a Standard block).
function Reveal.puff(self: any)
	local F = R.Flash
	local centre = self.centre
	local glow = Instance.new("ImageLabel")
	glow.Name = "ImpactGlow"
	glow.BackgroundTransparency = 1
	glow.Image = IMAGES.Glow
	glow.ImageColor3 = Color3.new(1, 1, 1)
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromOffset(centre.X, centre.Y)
	local from = self.side * 0.8
	glow.Size = UDim2.fromOffset(from, from)
	glow.ZIndex = 9
	glow.Parent = self.root
	local reach = self.side * F.GlowShare
	local grow = TweenService:Create(
		glow,
		TweenInfo.new(F.OutSeconds + F.InSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(reach, reach), ImageTransparency = 1 }
	)
	grow.Completed:Connect(function()
		glow:Destroy()
	end)
	grow:Play()
end

function Reveal.done(self: any)
	self.phase = "Done"
	self.hint.Visible = false -- it pops back in as "Tap to collect"
	if self.dotPulse then
		self.dotPulse.stop()
		self.dotPulse = nil
	end
	self.buffered = 0
	self.collectAt = os.clock() + R.DoneHintDelay
	local id = self.id
	if self.reply and self.reply.secret then
		-- No block to collect: a moment on the Secret, then its pull takes over.
		self.collectAt = math.huge
		task.delay(R.SecretHandOffSeconds, function()
			if self.open and self.phase == "Done" and self.id == id then
				local reply = self.reply
				self:finish(id, nil)
				self.deps.secret(reply)
			end
		end)
		return
	end
	task.delay(R.DoneHintDelay, function()
		if self.open and self.phase == "Done" and self.id == id then
			HudParts.setText(self.hint, hint(true))
			self:layout()
			self.hint.Visible = true
			UIAnim.popIn(self.hint)
			if not UIAnim.reduced() then
				self.hintPulse = UIAnim.bob(self.hint) -- a rock turns smoothly (a size pulse steps)
			end
		end
	end)
	task.delay(R.AutoCollect, function()
		if self.open and self.phase == "Done" and self.id == id then
			self:leave()
		end
	end)
end

-- The jump back into the hotbar (or, after a refusal, the block going back as it was).
function Reveal.leave(self: any)
	if not self.open or self.phase == "Leave" then
		return
	end
	self.phase = "Leave"
	self.anim = nil
	ContextActionService:UnbindAction(ACTION)
	if self.hintPulse then
		self.hintPulse.stop()
		self.hintPulse = nil
	end
	if self.dotPulse then
		self.dotPulse.stop()
		self.dotPulse = nil
	end
	self:showOthers()
	ScreenBlur.set(self, false)
	local L = R.Leave
	local fade = TweenInfo.new(L.FadeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, object in { self.title, self.hint, self.pill, self.ladder } do
		UIAnim.popOut(object)
	end
	for _, d in self.dots do
		UIAnim.popOut(d.frame)
	end
	TweenService:Create(self.glow, fade, { ImageTransparency = 1 }):Play()
	TweenService:Create(self.rays, fade, { ImageTransparency = 1 }):Play()
	TweenService:Create(self.wash, fade, { BackgroundTransparency = 1 }):Play()
	local id = self.id
	local kind = if self.reply and not self.failed then self.reply.kind else self.kind
	-- The hotbar comes back a frame or two later (Progression sees isOpen go false): the slot
	-- is looked up every frame of the flight, until it is there.
	local inset = GuiService:GetGuiInset()
	local side, _, size = self:metrics()
	local target = Vector2.new(size.X / 2, size.Y + side)
	local endScale = 0.25
	local aimed = false
	-- It leaves from where the float had it, so it never jumps.
	local from = self.pose.at + Vector2.new(0, (self.floatY or 0) - self.pose.lift)
	local fromScale = self.pose.scale
	local fromTurn = self.pose.turn + (self.floatTurn or 0)
	local reduced = UIAnim.reduced()
	self.anim = {
		seconds = L.Seconds,
		step = function(t: number)
			if not aimed then
				local slot, slotPx = self.deps.slotOf(id)
				if slot then
					aimed = true
					target = slot + Vector2.new(0, inset.Y)
					endScale = (slotPx or side * 0.25) / side
				end
			end
			local e = quadInOut(t)
			if reduced then
				self.pic.ImageTransparency = t
				return
			end
			self.pose.at = arc(from, target, size.Y * L.ArcShare, e)
			self.pose.scale = lerp(fromScale, endScale, e)
			self.pose.turn = L.ToTurn * math.sin(math.pi * t) + fromTurn * (1 - e)
			self.pose.lift = 0
		end,
		done = function()
			self:finish(id, kind)
		end,
	}
end

-- Gone: the slot shows its block again and bounces (`kind` nil: no block came back, the
-- Secret).
function Reveal.finish(self: any, id: number, kind: string?)
	if not self.open then
		return
	end
	self.open = false
	self.phase = "Closed"
	ContextActionService:UnbindAction(ACTION)
	RunService:UnbindFromRenderStep(SHAKE)
	if self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end
	if self.rainbow then
		self.rainbow.stop()
		self.rainbow = nil
	end
	self:showOthers()
	ScreenBlur.set(self, false)
	if self.gui then
		self.gui:Destroy()
		self.gui = nil
	end
	self.particles = {}
	self.deps.mask(id, false)
	if kind then
		self.deps.landed(id, kind)
	end
end

--- Closes at once (a match is starting): the block is already its tier in the save (or the
--- Secret cue the player's).
function Reveal.close(self: any)
	if self.open then
		local kind = if self.reply and not self.failed then self.reply.kind else self.kind
		self:finish(self.id, kind)
	end
end

---------------------------------------------------------------------------------------------
-- Every frame
---------------------------------------------------------------------------------------------

function Reveal.step(self: any, dt: number)
	if not self.open or self.gui == nil then
		return
	end
	dt *= self.timeScale or 1 -- Studio tests may slow it down (GuiQA "mysterySpeed")
	self.clock += dt
	local anim = self.anim
	if anim then
		anim.t = (anim.t or 0) + dt
		local t = clamp01(anim.t / anim.seconds)
		anim.step(t)
		if t >= 1 and self.anim == anim then
			self.anim = nil
			anim.done()
		end
	end
	local pose = self.pose
	local reduced = UIAnim.reduced()
	-- Floating from the moment it arrives, under the presses too (switching it off for a press
	-- would jump the block by the float's height).
	local floatY, floatTurn = 0, 0
	if not reduced and (self.phase == "Wait" or self.phase == "Press" or self.phase == "Done") then
		self.floatClock += dt
		local F = R.Float
		local w = 2 * math.pi * self.floatClock / F.Seconds
		floatY = math.sin(w) * self.side * F.HeightShare
		floatTurn = math.sin(w * 0.5) * F.Degrees
	end
	self.floatY, self.floatTurn = floatY, floatTurn
	local side = self.side
	if not reduced then
		self.rays.Rotation = (self.rays.Rotation + R.RaysDegreesPerSecond * dt) % 360
	end
	-- The impact's screen shake: the screen tilts a little (a turn is drawn smoothly) and the
	-- block jolts, on smooth noise fading out.
	local S = R.Shake
	local since = if self.shakeAt then self.clock - self.shakeAt else math.huge
	local sx, sy, sr = shakeNoise(since, 1), shakeNoise(since, 2), shakeNoise(since, 3)
	local jx, jy = 0, 0
	if sx and sy and sr then
		self.root.Rotation = S.Degrees * sr
		jx, jy = sx * side * S.BlockShare, sy * side * S.BlockShare
	elseif self.shakeAt then
		self.shakeAt = nil
		self.root.Rotation = 0
	end
	-- The block by whole pixels (its place and its size), and the leftover fractions by the
	-- window into its picture: GUI positions and sizes snap to whole pixels, so a slow move,
	-- squash or settle would step (the lively-gui smooth technique).
	local d = math.max(1, side * pose.scale)
	local x, y = pose.at.X + jx, pose.at.Y - pose.lift + floatY + jy
	local whole = math.max(1, math.floor(d + 0.5))
	local left = math.floor(x - whole / 2 + 0.5)
	local top = math.floor(y - whole / 2 + 0.5)
	self.holder.Position = UDim2.fromOffset(left, top)
	self.holder.Size = UDim2.fromOffset(whole, whole)
	self.holder.Rotation = pose.turn + floatTurn
	local border = R.IconBorder
	local texels = (R.IconPx - 2 * border) / d -- picture texels per screen pixel
	local window = whole * texels
	local room = math.max(0, R.IconPx - window)
	self.pic.ImageRectSize = Vector2.new(window, window)
	self.pic.ImageRectOffset = Vector2.new(
		math.clamp(border + (left - (x - d / 2)) * texels, 0, room),
		math.clamp(border + (top - (y - d / 2)) * texels, 0, room)
	)
	self:stepParticles(dt, self.clock)
end

return Reveal
