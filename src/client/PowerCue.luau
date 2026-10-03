--!strict
-- PowerCue: the power bar, with a cue lying in it.
--
-- A vertical panel on the right that you press and drag down. The fill charges up behind it
-- as before, and a top-down cue lies inside the bar and slides down as you pull, so the
-- control shows the thing it controls.
--
-- The cue is the catalog cue the player has equipped: its skin's rendered picture when it has
-- one (2026-10-03), else its colours drawn through CueArt (Catalog.style), so
-- the cue they pull back is the one on their stick - and a collectible cue is a data row,
-- never new code here. follow() keeps it on the player's EquippedCue. CueArt does the
-- arithmetic and is Lune-tested; this module only turns its slices into Frames.
--
-- In the UI kit's look (docs/UI_STYLE.md): a white track with an ink outline, and a fill that
-- runs green to yellow to red as the pull grows, then fades into the house rainbow from
-- Config.UI.PowerRainbowFromPower to all rainbow at 100%, its bands drifting down the bar.
--
-- While the local shooter's own Legendary or Mythic ability is armed, the fill wears that
-- ability's skin instead (Config.UI.PowerSkins, the designer 2026-09-30): its colours, a tiled
-- texture drifting down the bar, a flipbook crackling harder as the pull grows, an emblem
-- riding the fill's edge and spinning faster, and the outline glowing in its colour. Each
-- skin is a data row plus images; setSkin() builds the layers and one RenderStepped step
-- animates them while it shows.
--
-- A Frame cannot be a trapezoid, so the taper is built from thin bands stacked tip to butt.
-- Every position and size is in SCALE rather than pixels, so the whole control is resolution
-- independent and the pull reads the same on a phone and a monitor.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local CueArt = require(Shared:WaitForChild("CueArt"))
local CueStickBuilder = require(Shared:WaitForChild("CueStickBuilder"))
local Catalog = require(Shared:WaitForChild("Progression"):WaitForChild("Catalog"))
local CueSkins = require(Shared:WaitForChild("CueSkins"))
local HudParts = require(script.Parent.HudParts)
local TutorialAnchors = require(script.Parent.TutorialAnchors)
local K = Config.UI.Kit

local PowerCue = {}
PowerCue.__index = PowerCue

export type PowerCue = typeof(setmetatable(
	{} :: {
		root: TextButton,
		screen: ScreenGui,
		probe: ScreenGui, -- the whole screen, no safe area: measures the side inset
		fill: Frame,
		rainbow: UIGradient, -- the fill's rainbow near full pull, off below it
		rainbowStep: RBXScriptConnection?, -- drifts the rainbow while it shows
		rainbowBase: Color3, -- the green-to-red colour the rainbow fades from
		rainbowBlend: number, -- 0 (the base colour) ... 1 (all rainbow)
		stroke: UIStroke, -- the ink outline (a skin's glow tints it)
		skinId: string?, -- the armed ability whose skin shows (Config.UI.PowerSkins), if any
		skinParts: { Instance }, -- the skin's layers, destroyed when it goes
		skinTile: ImageLabel?,
		skinFlip: ImageLabel?,
		skinEmblem: ImageLabel?,
		skinStep: RBXScriptConnection?,
		tileY: number, -- the tile's drift, 0..Px
		flipT: number, -- the flipbook's frame clock
		text: TextLabel,
		cue: Frame,
		cueId: string, -- the catalog cue drawn
		pull: number?, -- the pull shown, nil when idle (PULL shows instead of a percentage)
		large: boolean?, -- the large-screen layout (place), nil before the first
		cueWidth: number, -- the cue's width at the butt, pixels, for this layout
		travel: number, -- how far the cue slides at full pull, in bar heights
	},
	PowerCue
))

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- The house rainbow along the bar, shifted by `phase` (0..1, one whole loop) and wrapping, so
-- the bands drift without a seam, mixed `blend` of the way from `base` (0: all base, 1: all
-- rainbow). Sampled at evenly spaced keypoints (ColorSequence keypoints must start at 0 and
-- end at 1, so the loop cannot simply be offset).
local KEYPOINTS = 13
local function rainbowAt(phase: number, base: Color3, blend: number): ColorSequence
	local colors = Config.Ranks.ChatRainbow
	local n = #colors
	local points = {}
	for i = 0, KEYPOINTS - 1 do
		local t = ((i / (KEYPOINTS - 1)) - phase) % 1 * n
		local a = math.floor(t)
		local from, to = rgb(colors[a % n + 1]), rgb(colors[(a + 1) % n + 1])
		local color = base:Lerp(from:Lerp(to, t - a), blend)
		table.insert(points, ColorSequenceKeypoint.new(i / (KEYPOINTS - 1), color))
	end
	return ColorSequence.new(points)
end

-- The cue nearly fills the bar at rest and slides a whole bar height at full pull, so it
-- leaves the bar entirely rather than stopping at its bottom edge.
local function cueLengthScale(): number
	return Config.UI.PowerCueLengthScale
end

--- Build the cue out of slices. Called once; pulling only moves the container.
local function buildCue(parent: GuiObject, cueId: string, width: number): Frame
	local U = Config.UI
	local style = Catalog.style(cueId) -- an unknown id draws the default cue

	local cue = Instance.new("Frame")
	cue.Name = "Cue"
	cue.AnchorPoint = Vector2.new(0.5, 0)
	cue.Position = UDim2.fromScale(0.5, 0)
	cue.Size = UDim2.new(0, width, cueLengthScale(), 0)
	cue.BackgroundTransparency = 1
	-- Above the fill. Equal ZIndex would fall back to creation order, which works today and
	-- would quietly stop working the moment the fill is rebuilt or reordered.
	cue.ZIndex = 2
	cue.Parent = parent

	-- A cue with a skin shows its own rendered picture (the one the cards use, its 3D piece
	-- frozen in place; designer, 2026-10-03), turned so the tip points up. The picture has the
	-- cue on its diagonal, PowerCueArtDiagonal of the way across, so it is sized from the bar's
	-- height to match the band-drawn cue's length.
	local row = Catalog.get(cueId)
	local skin = CueSkins.index(if row then row.Id else cueId)
	if skin and skin.Thumb ~= "" then
		local art = Instance.new("ImageLabel")
		art.Name = "Art"
		art.BackgroundTransparency = 1
		art.Image = skin.Thumb
		art.ScaleType = Enum.ScaleType.Fit
		art.AnchorPoint = Vector2.new(0.5, 0.5)
		art.Position = UDim2.fromScale(0.5, 0.5)
		art.SizeConstraint = Enum.SizeConstraint.RelativeYY
		local side = 1 / (math.sqrt(2) * U.PowerCueArtDiagonal)
		art.Size = UDim2.fromScale(side, side)
		art.Rotation = -45
		art.ZIndex = 2
		art.Parent = cue
		task.spawn(function() -- fetched now, so the bar is never empty on the first shot
			ContentProvider:PreloadAsync({ art })
		end)
		return cue
	end

	local slices = CueArt.slices(style, U.PowerCueSlices)
	for i, slice in slices do
		local band = Instance.new("Frame")
		band.Name = ("Slice%02d"):format(i)
		band.AnchorPoint = Vector2.new(0.5, 0)
		band.Position = UDim2.fromScale(0.5, slice.offset)
		-- One pixel of overlap, or rounding between bands leaves hairline gaps down the cue.
		band.Size = UDim2.new(0, math.max(1, math.round(slice.width * width)), slice.length, 1)
		band.BackgroundColor3 = rgb(slice.color)
		band.BorderSizePixel = 0
		band.ZIndex = 2
		band.Parent = cue

		-- Round the two ends only: a cue is blunt at the butt and domed at the tip.
		if i == 1 or i == #slices then
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.5, 0)
			corner.Parent = band
		end
	end
	return cue
end

--- The power bar, its cue drawn as catalog cue `cueId` (default: the default cue).
function PowerCue.new(screen: ScreenGui, cueId: string?): PowerCue
	local U = Config.UI

	-- An empty ScreenGui over the whole screen: its right edge minus the HUD's is the safe
	-- area's right strip (PowerCue.place).
	local probe = Instance.new("ScreenGui")
	probe.Name = "PowerSafeProbe"
	probe.ScreenInsets = Enum.ScreenInsets.None
	probe.IgnoreGuiInset = true
	probe.ResetOnSpawn = false
	probe.Enabled = true
	probe.Parent = screen.Parent

	-- The bar is the drag target, so it is a button rather than a frame.
	local bar = Instance.new("TextButton")
	bar.Name = "PowerBar"
	bar.Text = ""
	-- Where it sits and how big it is depend on the screen (PowerCue.place, every frame).
	bar.BackgroundColor3 = rgb(K.Colors.White)
	bar.BackgroundTransparency = U.PowerBarTransparency
	bar.AutoButtonColor = false
	bar.Parent = screen
	TutorialAnchors.set("PowerBar", bar) -- the tutorial lane's hand pulls it

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, K.ButtonCornerPx)
	corner.Parent = bar

	local stroke = Instance.new("UIStroke")
	stroke.Color = rgb(K.Colors.Ink)
	stroke.Thickness = K.ButtonStrokePx
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = bar
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Color = ColorSequence.new(rgb(K.Colors.White), rgb(K.PanelFade))
	fade.Parent = bar

	-- Fill charges from the top as the player pulls down, behind the cue.
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = rgb(K.Colors.Green)
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 0)
	fill.ZIndex = 1
	fill.ClipsDescendants = true -- a skin's layers show only where the fill has charged
	fill.Parent = bar
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, K.ButtonCornerPx)
	fillCorner.Parent = fill
	-- The rainbow near full pull: top to bottom along the fill, off until the pull gets there.
	local rainbow = Instance.new("UIGradient")
	rainbow.Name = "Rainbow"
	rainbow.Rotation = 90
	rainbow.Color = rainbowAt(0, Color3.new(1, 1, 1), 1)
	rainbow.Enabled = false
	rainbow.Parent = fill

	local shown = cueId or Config.Cue.DefaultStyle
	local cue = buildCue(bar, shown, U.PowerCueWidthPx)

	local text = HudParts.text(bar, "Percent", U.PowerLabelSize, Strings.Pull)
	text.TextWrapped = false
	text.Size = UDim2.new(1, 16, 0, U.PowerLabelSize + 6)
	-- ABOVE the bar. At full pull the cue hangs well below it, and a label underneath would
	-- be sitting behind the cue exactly when it has the most to say.
	text.AnchorPoint = Vector2.new(0.5, 1)
	text.Position = UDim2.new(0.5, 0, 0, -4)

	local self = setmetatable({
		root = bar,
		screen = screen,
		probe = probe,
		fill = fill,
		rainbow = rainbow,
		rainbowStep = nil,
		rainbowBase = Color3.new(1, 1, 1),
		rainbowBlend = 0,
		stroke = stroke,
		skinId = nil,
		skinParts = {},
		skinTile = nil,
		skinFlip = nil,
		skinEmblem = nil,
		skinStep = nil,
		tileY = 0,
		flipT = 0,
		text = text,
		cue = cue,
		cueId = shown,
		pull = nil,
		large = nil,
		cueWidth = U.PowerCueWidthPx,
		travel = U.PowerCueTravelScale,
	}, PowerCue)
	return self
end

--- Size and place the bar for this frame (Main calls it every frame, with the bottom of the
--- match top bar in pixels). A phone (shorter than Style.ShortHeight) keeps it high on the
--- right, under the top bar with room for PULL above, so the cue can hang a whole bar height
--- below it at full pull. A computer or tablet gets a bigger bar centred on the right edge
--- (designer, 2026-09-26); the cue there slides PowerLargeCueTravelScale of the bar so it
--- stays on the screen.
function PowerCue.place(self: PowerCue, headerBottom: number)
	local U, M = Config.UI, Config.Multiplayer
	local screenHeight = self.screen.AbsoluteSize.Y
	local large = screenHeight >= M.Style.ShortHeight
	local bar = self.root
	if large ~= self.large then
		self.large = large
		self.travel = if large then U.PowerLargeCueTravelScale else U.PowerCueTravelScale
		HudParts.setTextSize(self.text, if large then U.PowerLargeLabelSize else U.PowerLabelSize)
		self.cueWidth = if large then U.PowerLargeCueWidthPx else U.PowerCueWidthPx
		self.cue:Destroy()
		self.cue = buildCue(bar, self.cueId, self.cueWidth)
		self:setPull(self.pull)
	end
	if large then
		local height = math.clamp(
			screenHeight * U.PowerBarLargeHeightFraction,
			U.PowerBarMinHeightPx,
			U.PowerBarLargeMaxHeightPx
		)
		bar.AnchorPoint = Vector2.new(1, 0.5)
		bar.Position = UDim2.new(
			1,
			-U.PowerBarRightMarginPx,
			0.5,
			-screenHeight * U.PowerBarLargeRaiseFraction
		)
		bar.Size = UDim2.fromOffset(U.PowerBarLargeWidthPx, height)
	else
		-- Under the top bar, leaving room for its PULL label above it.
		local top = headerBottom + M.Style.HeaderGap + U.PowerLabelSize + 6
		local available = math.max(M.Style.ButtonHeight, screenHeight - top - M.Style.ButtonHeight)
		local height = math.min(U.PowerBarMaxHeightPx, available)
		-- Into part of the safe area's right strip, away from the aiming thumb.
		local inset = math.max(
			0,
			self.probe.AbsolutePosition.X
				+ self.probe.AbsoluteSize.X
				- (self.screen.AbsolutePosition.X + self.screen.AbsoluteSize.X)
		)
		local right = U.PowerBarPhoneRightMarginPx - inset * U.PowerBarPhoneInsetShare
		bar.AnchorPoint = Vector2.new(1, 0)
		bar.Position = UDim2.new(1, -math.floor(right), 0, top)
		bar.Size = UDim2.fromOffset(U.PowerBarWidthPx, height)
	end
end

--- Show this pull: the cue slides down, the fill charges up behind it, the label follows.
--- nil means idle, which is the same place as zero.
function PowerCue.setPull(self: PowerCue, pull: number?)
	local value = math.clamp(pull or 0, 0, 1)
	self.pull = pull and value
	self.cue.Position = UDim2.fromScale(0.5, value * self.travel)
	self.fill.Size = UDim2.fromScale(1, value)
	-- Green for a soft touch, through yellow, to red near full power; from
	-- PowerRainbowFromPower it fades into the house rainbow, all rainbow at 100% (as the
	-- label rounds it), drifting down the bar.
	local percent = math.floor(value * 100 + 0.5)
	local green, yellow, red = rgb(K.Colors.Green), rgb(K.Colors.Gold), rgb(K.Colors.Red)
	local base = if value < 0.5
		then green:Lerp(yellow, value * 2)
		else yellow:Lerp(red, (value - 0.5) * 2)
	local from = math.clamp(Config.UI.PowerRainbowFromPower, 0, 0.99)
	local k = math.clamp((value - from) / (1 - from), 0, 1)
	local blend = if pull == nil then 0 elseif percent >= 100 then 1 else k * k * (3 - 2 * k)
	self:showRainbow(base, blend)
	self.text.Text = if pull then Strings.PowerPercent:format(percent) else Strings.Pull
end

-- The fill's colour: `base` alone at blend 0, else the gradient mixing it `blend` of the way
-- into the rainbow (the fill turns white under it, as a gradient tints its background), its
-- bands drifting down the bar every frame while it shows.
function PowerCue.showRainbow(self: PowerCue, base: Color3, blend: number)
	self.rainbowBase, self.rainbowBlend = base, blend
	local skin = self.skinId and Config.UI.PowerSkins[self.skinId]
	if skin then
		-- A skin's own colours replace green-to-red and the rainbow.
		if self.rainbowStep then
			self.rainbowStep:Disconnect()
			self.rainbowStep = nil
		end
		local fill = skin.Fill or { K.Colors.White, K.Colors.White }
		self.fill.BackgroundColor3 = Color3.new(1, 1, 1)
		self.rainbow.Color = ColorSequence.new(rgb(fill[1]), rgb(fill[2]))
		self.rainbow.Enabled = true
		return
	end
	local on = blend > 0
	self.fill.BackgroundColor3 = if on then Color3.new(1, 1, 1) else base
	if on == self.rainbow.Enabled then
		return -- the running step picks up the new base and blend
	end
	self.rainbow.Enabled = on
	if self.rainbowStep then
		self.rainbowStep:Disconnect()
		self.rainbowStep = nil
	end
	if on then
		local started = os.clock()
		local cycle = math.max(Config.UI.PowerFullRainbowCycleSeconds, 0.05)
		local function paint()
			local phase = (os.clock() - started) / cycle % 1
			self.rainbow.Color = rainbowAt(phase, self.rainbowBase, self.rainbowBlend)
		end
		paint()
		self.rainbowStep = RunService.RenderStepped:Connect(paint)
	end
end

local function skinImage(parent: Instance, name: string, image: string, z: number): ImageLabel
	local label = Instance.new("ImageLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Image = image
	label.ZIndex = z
	label.Parent = parent
	return label
end

-- Every frame while a skin shows: the tile drifts, the flipbook turns its frames, the emblem
-- rides the fill's edge and spins, the outline glows; all faster or stronger with the pull.
function PowerCue.stepSkin(self: PowerCue, dt: number)
	local skin = self.skinId and Config.UI.PowerSkins[self.skinId]
	if skin == nil then
		return
	end
	local pull = self.pull or 0
	local floor = Config.UI.PowerSkinMinShare
	local barHeight = self.root.AbsoluteSize.Y
	local tile, t = self.skinTile, skin.Tile
	if tile and t then
		local px = t.Px
		self.tileY = (self.tileY + t.DriftPxPerSecond * (floor + (1 - floor) * pull) * dt) % px
		tile.Size = UDim2.new(1, 0, 0, barHeight + px)
		tile.Position = UDim2.fromOffset(0, self.tileY - px)
	end
	local flip, f = self.skinFlip, skin.Flipbook
	if flip and f then
		self.flipT += dt * (f.MinFps + (f.Fps - f.MinFps) * pull)
		local frame = math.floor(self.flipT) % (f.Cols * f.Rows)
		local w, h = f.FramePx[1], f.FramePx[2]
		flip.ImageRectOffset = Vector2.new((frame % f.Cols) * w, math.floor(frame / f.Cols) * h)
		flip.Size = UDim2.new(1, 0, 0, barHeight)
		flip.ImageTransparency = 1 - (f.MinShare + (1 - f.MinShare) * pull)
	end
	local emblem, e = self.skinEmblem, skin.Emblem
	if emblem and e then
		local spin = e.MinSpinDegPerSecond + (e.SpinDegPerSecond - e.MinSpinDegPerSecond) * pull
		emblem.Rotation = (emblem.Rotation + spin * dt) % 360
		emblem.Position = UDim2.fromScale(0.5, pull)
		emblem.Visible = self.pull ~= nil and pull >= Config.Input.MinPowerToShoot
	end
	if skin.Glow then
		-- A hint of the colour while armed, all of it at full pull.
		local k = floor + (1 - floor) * pull ^ 1.5
		self.stroke.Color = rgb(K.Colors.Ink):Lerp(rgb(skin.Glow), k)
	end
end

--- Dress the bar for armed ability `id` (a Config.UI.PowerSkins row), or nil (or an ability
--- with no row) for the plain bar. Nothing happens when it is already showing that.
function PowerCue.setSkin(self: PowerCue, id: string?)
	local skin = if id then Config.UI.PowerSkins[id] else nil
	local want = if skin then id else nil
	if want == self.skinId then
		return
	end
	for _, part in self.skinParts do
		part:Destroy()
	end
	table.clear(self.skinParts)
	self.skinTile, self.skinFlip, self.skinEmblem = nil, nil, nil
	if self.skinStep then
		self.skinStep:Disconnect()
		self.skinStep = nil
	end
	self.stroke.Color = rgb(K.Colors.Ink)
	self.rainbow.Enabled = false
	self.skinId = want
	if skin then
		if skin.Tile then
			local tile = skinImage(self.fill, "SkinTile", skin.Tile.Image, 1)
			tile.ScaleType = Enum.ScaleType.Tile
			tile.TileSize = UDim2.fromOffset(skin.Tile.Px, skin.Tile.Px)
			self.skinTile = tile
			table.insert(self.skinParts, tile)
		end
		if skin.Flipbook then
			local f = skin.Flipbook
			local flip = skinImage(self.fill, "SkinFlipbook", f.Image, 1)
			flip.ImageRectSize = Vector2.new(f.FramePx[1], f.FramePx[2])
			self.skinFlip = flip
			table.insert(self.skinParts, flip)
		end
		if skin.Emblem then
			-- Over the cue: it rides the fill's edge, where the cue's tip is.
			local emblem = skinImage(self.root, "SkinEmblem", skin.Emblem.Image, 3)
			emblem.AnchorPoint = Vector2.new(0.5, 0.5)
			emblem.SizeConstraint = Enum.SizeConstraint.RelativeXX
			emblem.Size = UDim2.fromScale(skin.Emblem.WidthShare, skin.Emblem.WidthShare)
			emblem.Visible = false
			self.skinEmblem = emblem
			table.insert(self.skinParts, emblem)
		end
		self.skinStep = RunService.RenderStepped:Connect(function(dt: number)
			self:stepSkin(dt)
		end)
		self:stepSkin(0)
	end
	self:setPull(self.pull)
end

--- Rebuild for a different catalog cue (nothing happens for the one already drawn).
function PowerCue.setCue(self: PowerCue, cueId: string)
	if cueId == self.cueId then
		return
	end
	self.cueId = cueId
	self.cue:Destroy()
	self.cue = buildCue(self.root, cueId, self.cueWidth)
	self:setPull(self.pull)
end

--- Draw `player`'s equipped cue (Config.Cue.EquippedAttribute) from now on, and redraw it
--- whenever they equip another. Call once.
function PowerCue.follow(self: PowerCue, player: Player)
	local function show()
		self:setCue(CueStickBuilder.equippedCue(player))
	end
	player:GetAttributeChangedSignal(Config.Cue.EquippedAttribute):Connect(show)
	show()
end

function PowerCue.setVisible(self: PowerCue, visible: boolean)
	self.root.Visible = visible
	if not visible then
		self:setPull(nil)
	end
end

--- Press the bar and drag down to pull back. `onPull` fires with 0..1 while dragging,
--- `onRelease` when the finger lifts.
function PowerCue.onDrag(self: PowerCue, onPull: (number) -> (), onRelease: () -> ())
	local active: InputObject? = nil
	local startY = 0

	self.root.InputBegan:Connect(function(input: InputObject)
		if active then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			active = input
			startY = input.Position.Y
			onPull(0)
		end
	end)

	UserInputService.InputChanged:Connect(function(input: InputObject)
		local a = active
		if a == nil then
			return
		end
		-- A mouse reports its drag as MouseMovement rather than as the button that started
		-- it, so the two have to be treated as the same gesture.
		local same = input == a
			or (
				a.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseMovement
			)
		if same then
			local travel = self.root.AbsoluteSize.Y * Config.Input.PowerPullBarFraction
			onPull(math.clamp((input.Position.Y - startY) / math.max(travel, 1), 0, 1))
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		local a = active
		if a == nil then
			return
		end
		if
			input == a
			or (
				a.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseButton1
			)
		then
			active = nil
			onRelease()
		end
	end)
end

return PowerCue
