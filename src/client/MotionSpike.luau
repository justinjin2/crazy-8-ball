--!strict
-- MotionSpike: the lively Shop's gate 1 test screen (docs/prompts/SHOP_LIVELY_PROMPT.md 7.1),
-- Studio only, opened with PlayerScripts.GuiQA:Invoke("spike") and closed the same way. It
-- shows each way of moving something slowly side by side at one speed, so the smooth one can
-- be picked from a 60 fps recording. Roblox draws GUI positions and sizes in whole pixels, so
-- the candidates move the picture inside a still label (fractional ImageRectOffset and
-- ImageRectSize), use Scale positions, crossfade two copies a pixel apart, or draw in 3D.
--
--   Row 1, the header scroll at 45 degrees up-left: (a) a window into a 2 x 2 seamless tile
--   slid by fractional ImageRectOffset, (b) a Tile label moved by Scale, (c) two Tile labels a
--   pixel apart crossfaded by the fraction, (d) a ViewportFrame with a scrolling Texture.
--   Row 2, a floating ball and a breathing ball: whole pixels plus the fraction in
--   ImageRectOffset, a plain Position, a Scale Position; ImageRectSize zoom against UIScale.
--   Row 3, a pop with the code fade against a CanvasGroup fade, the unroll of a native panel,
--   the 64-frame firework flipbook and a pooled particle burst.
--
-- GuiQA "spikeRate" slows everything (0.1 = ten times slower) for screen_capture.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GuiQA = require(script.Parent.GuiQA)
local HudParts = require(script.Parent.HudParts)
local UIAnim = require(script.Parent.UIAnim)

local C = Config.Debug.MotionSpike
local K = Config.UI.Kit
local color = HudParts.color

local MotionSpike = {}

local gui: ScreenGui? = nil
local rate = 1 -- the slow-motion multiplier
local clock = 0
local steps: { (number, number) -> () } = {}

local function label(parent: Instance, text: string, x: number, y: number)
	local words = Instance.new("TextLabel")
	words.Name = "Label"
	words.BackgroundTransparency = 1
	words.Font = Enum.Font.GothamBold
	words.TextSize = 14
	words.TextColor3 = Color3.new(1, 1, 1)
	words.TextXAlignment = Enum.TextXAlignment.Left
	words.Text = text
	words.Position = UDim2.fromOffset(x, y)
	words.Size = UDim2.fromOffset(340, 18)
	words.Parent = parent
end

-- A header-like band: the pale-blue gradient, an ink edge, clipping its contents.
local function band(parent: Instance, x: number, y: number, w: number, h: number): Frame
	local frame = HudParts.frame(parent, "Band")
	frame.BackgroundTransparency = 0
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.ClipsDescendants = true
	frame.Position = UDim2.fromOffset(x, y)
	frame.Size = UDim2.fromOffset(w, h)
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Color = ColorSequence.new(color(K.HeaderTop), color(K.HeaderBottom))
	fade.Parent = frame
	return frame
end

local function image(parent: Instance, name: string, art: string): ImageLabel
	local img = Instance.new("ImageLabel")
	img.Name = name
	img.BackgroundTransparency = 1
	img.Image = art
	img.Parent = parent
	return img
end

-- How far the pattern has scrolled, in screen pixels on each axis (up-left: positive).
local function scrolled(): number
	return clock * C.ScrollPxPerSecond
end

--------------------------------------------------------------------------------------------
-- Row 1: the header scroll
--------------------------------------------------------------------------------------------

local function scrollRect(parent: Instance, x: number, y: number, w: number, h: number)
	local frame = band(parent, x, y, w, h)
	local texel = C.PatternPeriod / C.PatternTilePx -- texels per screen pixel
	local img = image(frame, "Window", C.Pattern2x2)
	img.Size = UDim2.fromScale(1, 1)
	img.ScaleType = Enum.ScaleType.Stretch
	img.ImageTransparency = C.PatternTransparency
	img.ImageRectSize = Vector2.new(w * texel, h * texel)
	table.insert(steps, function()
		-- The picture moves up-left, so the window moves down-right through the texture.
		local o = (scrolled() * texel) % C.PatternPeriod
		img.ImageRectOffset = Vector2.new(o, o)
	end)
end

local function scrollScale(parent: Instance, x: number, y: number, w: number, h: number)
	local frame = band(parent, x, y, w, h)
	local tile = C.PatternTilePx
	local img = image(frame, "Tiles", C.PatternTile)
	img.ScaleType = Enum.ScaleType.Tile
	img.TileSize = UDim2.fromOffset(tile, tile)
	img.ImageTransparency = C.PatternTransparency
	img.Size = UDim2.new(1, tile, 1, tile)
	table.insert(steps, function()
		local f = (scrolled() % tile) / tile
		img.Position = UDim2.fromScale(-f * tile / w, -f * tile / h)
	end)
end

local function scrollCrossfade(parent: Instance, x: number, y: number, w: number, h: number)
	local frame = band(parent, x, y, w, h)
	local tile = C.PatternTilePx
	local function layer(name: string): ImageLabel
		local img = image(frame, name, C.PatternTile)
		img.ScaleType = Enum.ScaleType.Tile
		img.TileSize = UDim2.fromOffset(tile, tile)
		img.Size = UDim2.new(1, tile + 2, 1, tile + 2)
		return img
	end
	local low, high = layer("Low"), layer("High")
	local base = C.PatternTransparency
	table.insert(steps, function()
		local p = scrolled() % tile
		local whole = math.floor(p)
		local frac = p - whole
		low.Position = UDim2.fromOffset(-whole, -whole)
		high.Position = UDim2.fromOffset(-whole - 1, -whole - 1)
		-- Opacities (1 - frac) and frac of the pattern's own strength.
		low.ImageTransparency = 1 - (1 - base) * (1 - frac)
		high.ImageTransparency = 1 - (1 - base) * frac
	end)
end

local function scrollViewport(parent: Instance, x: number, y: number, w: number, h: number)
	local frame = band(parent, x, y, w, h)
	local view = Instance.new("ViewportFrame")
	view.Name = "View"
	view.BackgroundTransparency = 1
	view.Size = UDim2.fromScale(1, 1)
	view.Ambient = Color3.new(1, 1, 1)
	view.LightColor = Color3.new(0, 0, 0)
	view.Parent = frame
	-- A part exactly filling the view: 1 stud per 10 px.
	local studs = Vector2.new(w, h) / 10
	local part = Instance.new("Part")
	part.Anchored = true
	part.Size = Vector3.new(studs.X, studs.Y, 0.2)
	part.CFrame = CFrame.new()
	part.Color = color(K.HeaderTop) -- a Texture on a fully clear part does not draw
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = view
	local texture = Instance.new("Texture")
	texture.Face = Enum.NormalId.Front
	texture.Texture = C.PatternTile
	texture.Transparency = C.PatternTransparency
	texture.StudsPerTileU = C.PatternTilePx / 10
	texture.StudsPerTileV = C.PatternTilePx / 10
	texture.Parent = part
	local camera = Instance.new("Camera")
	camera.FieldOfView = 20
	local distance = (studs.Y / 2) / math.tan(math.rad(camera.FieldOfView / 2))
	-- The front face is -Z: look at it from in front.
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 0, -distance - 0.1), Vector3.new(0, 0, 0))
	camera.Parent = view
	view.CurrentCamera = camera
	table.insert(steps, function()
		local s = scrolled() / 10 -- no wrap: a texture offset repeats by itself
		texture.OffsetStudsU = s
		texture.OffsetStudsV = s
	end)
end

--------------------------------------------------------------------------------------------
-- Row 2: float and breathe
--------------------------------------------------------------------------------------------

local function float(): number
	return C.FloatPx * math.sin(2 * math.pi * clock / C.FloatSeconds)
end

-- Whole-pixel Position plus the leftover fraction moved inside the picture.
local function floatRect(parent: Instance, x: number, y: number)
	local px, border = C.BallPx, C.BallBorder
	local inner = 256 - 2 * border + 8 -- a window a little bigger than the ball
	local texel = inner / px
	local img = image(parent, "FloatRect", C.Ball)
	img.Size = UDim2.fromOffset(px, px)
	img.ImageRectSize = Vector2.new(inner, inner)
	local start = (256 - inner) / 2
	table.insert(steps, function()
		local dy = float()
		local whole = math.floor(dy + 0.5)
		img.Position = UDim2.fromOffset(x, y + whole)
		-- Show the ball (dy - whole) px lower: move the window up by that many texels.
		img.ImageRectOffset = Vector2.new(start, start - (dy - whole) * texel)
	end)
end

local function floatOffset(parent: Instance, x: number, y: number)
	local img = image(parent, "FloatOffset", C.Ball)
	img.Size = UDim2.fromOffset(C.BallPx, C.BallPx)
	table.insert(steps, function()
		img.Position = UDim2.fromOffset(x, y + float())
	end)
end

local function floatScale(parent: Instance, x: number, y: number)
	local img = image(parent, "FloatScale", C.Ball)
	img.Size = UDim2.fromOffset(C.BallPx, C.BallPx)
	table.insert(steps, function()
		local height = (parent :: GuiObject).AbsoluteSize.Y
		img.Position = UDim2.new(0, x, (y + float()) / math.max(1, height), 0)
	end)
end

local function breathe(): number
	return 1 + C.BreatheScale * math.sin(2 * math.pi * clock / C.BreatheSeconds)
end

local function breatheRect(parent: Instance, x: number, y: number)
	local px = C.BallPx
	local img = image(parent, "BreatheRect", C.Ball)
	img.Position = UDim2.fromOffset(x, y)
	img.Size = UDim2.fromOffset(px, px)
	table.insert(steps, function()
		-- A smaller window shows the ball bigger. The window stays inside the image (Roblox
		-- clamps a rect past its edge), so it breathes round one inside the clear border.
		local base = 256 - C.BallBorder
		local size = base / breathe()
		local at = (256 - size) / 2
		img.ImageRectSize = Vector2.new(size, size)
		img.ImageRectOffset = Vector2.new(at, at)
	end)
end

local function breatheScale(parent: Instance, x: number, y: number)
	local img = image(parent, "BreatheScale", C.Ball)
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.Position = UDim2.fromOffset(x + C.BallPx / 2, y + C.BallPx / 2)
	img.Size = UDim2.fromOffset(C.BallPx, C.BallPx)
	local scale = Instance.new("UIScale")
	scale.Parent = img
	table.insert(steps, function()
		scale.Scale = breathe()
	end)
end

--------------------------------------------------------------------------------------------
-- Row 3: pop, unroll, flipbook, particles
--------------------------------------------------------------------------------------------

local function backOut(t: number, s: number): number
	local x = math.clamp(t, 0, 1) - 1
	return 1 + (s + 1) * x * x * x + s * x * x
end

-- A small kit card (white, ink outline, a title and an icon).
local function popCard(parent: Instance, name: string): Frame
	local card = HudParts.card(parent, name)
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Size = UDim2.fromOffset(150, 70)
	local words = HudParts.text(card, "Title", 24, "SHOP")
	words.Position = UDim2.fromOffset(56, 8)
	words.Size = UDim2.fromOffset(86, 54)
	words.ZIndex = 2
	local icon = HudParts.icon(card, "ShopBasket", "Icon")
	icon.Position = UDim2.fromOffset(8, 11)
	icon.Size = UDim2.fromOffset(48, 48)
	icon.ZIndex = 2
	return card
end

-- Every fading property of a subtree, cached at rest (the code fader).
local function fader(root: Instance): (number) -> ()
	local cache: { { object: Instance, prop: string, rest: number } } = {}
	local props = {
		Frame = { "BackgroundTransparency" },
		ImageLabel = { "BackgroundTransparency", "ImageTransparency" },
		TextLabel = { "BackgroundTransparency", "TextTransparency", "TextStrokeTransparency" },
		UIStroke = { "Transparency" },
	}
	for _, object in root:GetDescendants() do
		local list = props[object.ClassName]
		if list then
			for _, prop in list do
				table.insert(cache, { object = object, prop = prop, rest = (object :: any)[prop] })
			end
		end
	end
	return function(alpha: number)
		for _, c in cache do
			(c.object :: any)[c.prop] = 1 - (1 - c.rest) * alpha
		end
	end
end

local function popCode(parent: Instance, x: number, y: number)
	local card = popCard(parent, "PopCode")
	card.Position = UDim2.fromOffset(x, y)
	local scale = Instance.new("UIScale")
	scale.Parent = card
	local fade = fader(card)
	table.insert(steps, function()
		local t = clock % C.PopEvery
		scale.Scale = 0.6 + 0.4 * backOut(t / 0.22, 2.2)
		fade(math.clamp(t / 0.1, 0, 1))
	end)
end

local function popCanvas(parent: Instance, x: number, y: number)
	local group = Instance.new("CanvasGroup")
	group.Name = "PopCanvas"
	group.BackgroundTransparency = 1
	group.AnchorPoint = Vector2.new(0.5, 0.5)
	group.Position = UDim2.fromOffset(x, y)
	group.Size = UDim2.fromOffset(190, 110) -- room for the shadow
	group.Parent = parent
	local card = popCard(group, "Card")
	card.Position = UDim2.fromScale(0.5, 0.5)
	local scale = Instance.new("UIScale")
	scale.Parent = group
	table.insert(steps, function()
		local t = clock % C.PopEvery
		scale.Scale = 0.6 + 0.4 * backOut(t / 0.22, 2.2)
		group.GroupTransparency = 1 - math.clamp(t / 0.1, 0, 1)
	end)
end

local function unroll(parent: Instance, x: number, y: number)
	local w, h = 260, 120
	local panel = HudParts.card(parent, "Unroll")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromOffset(x, y)
	table.insert(steps, function()
		local t = clock % C.PopEvery
		-- A thin bar (the outline and a sliver of white) opens up and down with an overshoot.
		local bar = 10
		local k = backOut(math.max(0, t - 0.15) / 0.2, 1.4)
		panel.Size = UDim2.fromOffset(w, math.floor(bar + (h - bar) * k + 0.5))
	end)
end

local function flipbook(parent: Instance, x: number, y: number)
	local tints = { { 255, 92, 184 }, { 82, 196, 255 }, { 255, 201, 40 } }
	for i, tint in tints do
		local img = image(parent, "Firework" .. i, C.Firework)
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Position = UDim2.fromOffset(x + (i - 2) * 60, y + (if i == 2 then -20 else 10))
		img.Size = UDim2.fromOffset(110, 110)
		img.ImageColor3 = color(tint)
		img.ImageRectSize = Vector2.new(128, 128)
		local phase = (i - 1) * 0.5
		table.insert(steps, function()
			local frame = math.floor((clock + phase) * C.FireworkFps) % 64
			img.ImageRectOffset = Vector2.new((frame % 8) * 128, math.floor(frame / 8) * 128)
		end)
	end
end

local function particles(parent: Instance, x: number, y: number)
	local pool: { ImageLabel } = {}
	local random = Random.new(8)
	local spark: { { vx: number, vy: number, spin: number } } = {}
	for i = 1, C.Particles do
		local img = image(parent, "Spark" .. i, C.Spark)
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.ImageColor3 = color(i % 2 == 0 and { 255, 214, 10 } or { 255, 255, 255 })
		img.Visible = false
		pool[i] = img
		local angle = random:NextNumber(0, 2 * math.pi)
		local speed = random:NextNumber(60, 150)
		spark[i] = {
			vx = math.cos(angle) * speed,
			vy = math.sin(angle) * speed - 40,
			spin = random:NextNumber(-360, 360),
		}
	end
	table.insert(steps, function()
		local t = clock % C.ParticleEvery
		local life = 0.9
		for i, img in pool do
			local s = spark[i]
			if t > life then
				img.Visible = false
			else
				img.Visible = true
				local k = t / life
				img.Position = UDim2.fromOffset(x + s.vx * t, y + s.vy * t + 160 * t * t)
				local size = 16 * (1 - k * 0.6)
				img.Size = UDim2.fromOffset(size, size)
				img.Rotation = s.spin * t
				img.ImageTransparency = k * k
			end
		end
	end)
end

--------------------------------------------------------------------------------------------
-- Open and close
--------------------------------------------------------------------------------------------

function MotionSpike.open(): boolean
	if gui then
		return true
	end
	local player = Players.LocalPlayer
	local made = Instance.new("ScreenGui")
	made.Name = "MotionSpike"
	made.IgnoreGuiInset = true
	made.ResetOnSpawn = false
	made.DisplayOrder = 500
	made.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui = made
	local root = HudParts.frame(made, "Root")
	root.BackgroundTransparency = 0
	root.BackgroundColor3 = Color3.fromRGB(16, 22, 48)
	root.Size = UDim2.fromScale(1, 1)
	table.clear(steps)
	clock = 0

	local x0, y0, w, h, gap = 20, 70, 340, 90, 24
	local titles = {
		"a) ImageRectOffset window",
		"b) Tile moved by Scale",
		"c) two Tiles crossfaded",
		"d) ViewportFrame Texture",
	}
	local makers = { scrollRect, scrollScale, scrollCrossfade, scrollViewport }
	for i, make in makers do
		local x = x0 + (i - 1) * (w + gap)
		label(root, titles[i], x, y0 - 22)
		make(root, x, y0, w, h)
	end

	local y1 = y0 + h + 60
	local cellTitles = {
		"float: px + rect",
		"float: Offset",
		"float: Scale",
		"breathe: RectSize",
		"breathe: UIScale",
	}
	local cellMakers = { floatRect, floatOffset, floatScale, breatheRect, breatheScale }
	for i, make in cellMakers do
		local x = x0 + (i - 1) * 200
		label(root, cellTitles[i], x, y1 - 22)
		make(root, x + 40, y1 + 14)
	end

	local y2 = y1 + 190
	label(root, "pop: UIScale + code fade", x0, y2 - 22)
	popCode(root, x0 + 100, y2 + 60)
	label(root, "pop: CanvasGroup", x0 + 240, y2 - 22)
	popCanvas(root, x0 + 340, y2 + 60)
	label(root, "unroll (native chrome)", x0 + 480, y2 - 22)
	unroll(root, x0 + 610, y2 + 60)
	label(root, "flipbook 8x8 @ 30 fps", x0 + 790, y2 - 22)
	flipbook(root, x0 + 900, y2 + 60)
	label(root, "pooled particles", x0 + 1060, y2 - 22)
	particles(root, x0 + 1140, y2 + 60)

	-- A time code for the measuring script (tools/gui/motion_measure.py): the motion clock in
	-- milliseconds, 16 bits, as squares (white = 1), most significant first. It tells the
	-- script which recorded frames are repeats and how much game time each step took.
	local bits: { Frame } = {}
	for i = 1, 16 do
		local bit = HudParts.frame(root, "Bit" .. i)
		bit.BackgroundTransparency = 0
		bit.Position = UDim2.fromOffset(C.CodeX + (i - 1) * C.CodeCellPx, C.CodeY)
		bit.Size = UDim2.fromOffset(C.CodeCellPx, C.CodeCellPx)
		bits[i] = bit
	end
	table.insert(steps, function()
		local ms = math.floor(clock * 1000) % 65536
		for i = 1, 16 do
			local on = bit32.extract(ms, 16 - i) == 1
			bits[i].BackgroundColor3 = if on then Color3.new(1, 1, 1) else Color3.new(0, 0, 0)
		end
	end)

	UIAnim.loop(root, function(_, dt)
		clock += dt * rate
		for _, step in steps do
			step(clock, dt)
		end
	end)
	made.Parent = player:WaitForChild("PlayerGui")
	return true
end

function MotionSpike.close(): boolean
	if gui then
		gui:Destroy()
		gui = nil
	end
	return true
end

function MotionSpike.start()
	if not RunService:IsStudio() then
		return
	end
	GuiQA.add("spike", function(on: boolean?)
		if on == false or (on == nil and gui ~= nil) then
			return MotionSpike.close()
		end
		return MotionSpike.open()
	end)
	-- Slide the whole test screen up by `px` (a phone's short view shows the lower rows).
	GuiQA.add("spikeShift", function(px: number)
		local made = gui
		local root = made and made:FindFirstChild("Root") :: Frame?
		if root then
			root.Position = UDim2.fromOffset(0, -px)
		end
		return px
	end)
	GuiQA.add("spikeRate", function(value: number)
		rate = value
		return rate
	end)
end

return MotionSpike
