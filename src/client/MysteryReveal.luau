--!strict
-- MysteryReveal: the Mystery block's upgrade screen (designer, 2026-10-07, like Star Drop but
-- our own; Config.LuckyBlocks.Reveal). A tap on a ready Mystery block's OPEN! slot jumps its 2D
-- icon out of the hotbar at the screen while the world blurs; it floats there with its tier's
-- particles over a glow and turning rays in the tier's colour. Each press (a tap, a click, A,
-- Space or Enter) squashes it; a press that changes the tier bounces it, then it turns into
-- the next block with an impact (a white flash, a screen shake and a burst; designer,
-- 2026-10-07: no spin), its name slamming in over it. A dot fills
-- per press in the colour that press showed. After the last press "Tap to collect" (or a few
-- seconds) shrinks the screen and the block jumps back into its hotbar slot.
--
-- The server decides everything first (BlockRequest "Reveal": the tier, with pity, and the path
-- of the presses, BlockDrop.path) and the block is already that tier's block in the save; this
-- screen only plays the path. Leaving or closing early loses nothing.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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

local R = Config.LuckyBlocks.Reveal
local IMAGES: { [string]: string } = R.Images :: any
local TIERS: { [string]: any } = R.Tiers :: any
local W = Strings.LuckyBlocks.Reveal
local CLICKS: number = Config.BlockOdds.Drop.Upgrade.Clicks
local ACTION = "MysteryRevealPress"
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
	local row = LuckyBlocks.kind(kind)
	return if row and row.Icon then row.Icon else ""
end

local function look(kind: string): any
	return TIERS[kind] or TIERS.Standard
end

local function hint(done: boolean): string
	if ReelFx.gamepad() then
		return if done then W.CollectPad else W.TapPad
	elseif ReelFx.touch() then
		return if done then W.Collect else W.Tap
	end
	return if done then W.CollectMouse else W.TapMouse
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

type Dot = { frame: Frame, fill: Frame, gloss: ImageLabel, mark: TextLabel, scale: UIScale }

export type Deps = {
	-- Asks the server to reveal block `id` (BlockRequest "Reveal"): { ok, tiers, kind } or a
	-- refusal { ok = false, reason }.
	request: (id: number) -> any,
	-- Where the block's hotbar slot is now (absolute pixels, top bar inset included in the
	-- hotbar's own space) and its size, or nil when the bar is hidden.
	slotOf: (id: number) -> (Vector2?, number?),
	-- The hotbar slot shows nothing while the block is out of it (true), or its block again.
	mask: (id: number, on: boolean) -> (),
	-- The block landed back in its slot, now a `kind` block.
	landed: (id: number, kind: string) -> (),
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
	wash.BackgroundColor3 = rgb(look("Mystery").Glow)
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

	local holder = HudParts.frame(root, "Block")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.ZIndex = 7
	self.holder = holder
	self.holderScale = UIAnim.scaleOf(holder)
	local pic = Instance.new("ImageLabel")
	pic.Name = "Picture"
	pic.BackgroundTransparency = 1
	pic.ScaleType = Enum.ScaleType.Fit
	pic.AnchorPoint = Vector2.new(0.5, 0.5)
	pic.Position = UDim2.fromScale(0.5, 0.5)
	pic.Size = UDim2.fromScale(1, 1)
	pic.ZIndex = 8
	pic.Parent = holder
	self.pic = pic

	local title = HudParts.text(root, "Title", 60, "")
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.TextWrapped = false
	title.Rotation = R.TitleTurnDegrees
	title.ZIndex = 10
	title.Visible = false
	self.title = title

	local label = HudParts.text(root, "Chances", 24, W.Chances)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.TextWrapped = false
	label.ZIndex = 10
	label.Visible = false
	self.label = label

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
		})
	end

	local hintLabel = HudParts.text(root, "Hint", 22, "")
	hintLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	hintLabel.TextWrapped = false
	hintLabel.ZIndex = 10
	hintLabel.Visible = false
	self.hint = hintLabel

	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:layout()
	end)
end

-- The block's side, its resting middle and the screen's size, in pixels.
function Reveal.metrics(self: any): (number, Vector2, Vector2)
	local size = self.gui.AbsoluteSize
	local side = math.min(size.Y * R.BlockShare, size.X * R.BlockMaxShareOfWidth)
	return side, Vector2.new(size.X / 2, size.Y * R.BlockY), size
end

function Reveal.layout(self: any)
	if self.gui == nil then
		return
	end
	local side, centre, size = self:metrics()
	self.side, self.centre = side, centre
	self.holder.Size = UDim2.fromOffset(side, side)
	self.glow.Size = UDim2.fromOffset(side * R.GlowShare, side * R.GlowShare)
	self.glow.Position = UDim2.fromOffset(centre.X, centre.Y)
	self.rays.Size = UDim2.fromOffset(side * R.RaysShare, side * R.RaysShare)
	self.rays.Position = UDim2.fromOffset(centre.X, centre.Y)
	local titleH = side * R.TitleHeightShare
	self.title.Size = UDim2.fromOffset(math.min(size.X * 0.94, side * R.TitleWidthShare), titleH)
	self.title.Position = UDim2.fromOffset(size.X / 2, size.Y * R.TitleY)
	HudParts.setTextSize(self.title, titleH)
	local labelH = side * R.LabelHeightShare
	self.label.Size = UDim2.fromOffset(math.min(size.X * 0.9, side * 1.6), labelH)
	self.label.Position = UDim2.fromOffset(size.X / 2, size.Y * R.LabelY)
	HudParts.setTextSize(self.label, labelH)
	local dot = side * R.DotShare
	local gap = side * R.DotGapShare
	local rowW = CLICKS * dot + (CLICKS - 1) * gap
	self.row.Size = UDim2.fromOffset(rowW, dot)
	self.row.Position = UDim2.fromOffset(size.X / 2, size.Y * R.DotsY)
	for i, d in self.dots do
		d.frame.Size = UDim2.fromOffset(dot, dot)
		d.frame.Position = UDim2.fromOffset((i - 1) * (dot + gap) + dot / 2, dot / 2)
		HudParts.setTextSize(d.mark, dot * 0.7)
	end
	local hintH = side * R.HintHeightShare
	self.hint.Size = UDim2.fromOffset(size.X * 0.9, hintH)
	self.hint.Position = UDim2.fromOffset(size.X / 2, size.Y * R.HintY)
	HudParts.setTextSize(self.hint, hintH)
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

-- The name over the block, its colour (or the rainbow) and the glow, rays and wash behind it.
function Reveal.showTier(self: any, kind: string, slam: boolean)
	self.shown = kind
	local tier = look(kind)
	self.pic.Image = iconOf(kind)
	local words = if kind == "Mystery" then W.Title else (W.Tiers[kind] or string.upper(kind))
	self.title.Text = words
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
	local scale = d.scale
	local handle = UIAnim.loop(d.frame, function(clock)
		if not UIAnim.reduced() then
			scale.Scale = 1 + P.Scale * (0.5 + 0.5 * math.sin(2 * math.pi * clock / P.Seconds))
		end
	end)
	self.dotPulse = {
		stop = function()
			handle.stop()
			scale.Scale = 1
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

--- Opens the screen for the ready Mystery block `id`: it jumps out of the hotbar slot at
--- `from` (absolute pixels in the hotbar's space, and the slot's size) while the server
--- reveals it. `fake` (Studio tests only, GuiQA "mystery"): a made-up reply, nothing asked.
function Reveal.play(self: any, id: number, from: Vector2?, fromPx: number?, fake: any?)
	if self.open then
		return
	end
	self.open = true
	self.id = id
	self.reply = nil
	self.presses = 0
	self.particles = {}
	self.carry = {}
	self.random = Random.new()
	self.buffered = 0
	self.anim = nil
	self.clock = 0
	self.floatClock = 0
	self:build()
	self:layout()
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
	task.spawn(function()
		local reply = if fake ~= nil then fake else self.deps.request(id)
		if not self.open or self.id ~= id then
			return
		end
		if
			type(reply) ~= "table"
			or not reply.ok
			or type(reply.tiers) ~= "table"
			or #reply.tiers ~= CLICKS
		then
			self.deps.refused(reply)
			self.failed = true
			self:leave()
			return
		end
		for _, tier in reply.tiers do
			if LuckyBlocks.kind(tier) == nil then
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
	self:showTier("Mystery", false)
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
			self.title.Visible = true
			UIAnim.slam(self.title, Color3.new(1, 1, 1))
		end
	end)
	task.delay(A.DotsAt, function()
		if not self.open or self.phase == "Leave" then
			return
		end
		self.label.Visible = true
		UIAnim.popIn(self.label)
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
		if self.open and self.phase ~= "Leave" and self.presses == 0 then
			self.hint.Text = hint(false)
			self.hint.Visible = true
			UIAnim.popIn(self.hint)
		end
	end)
end

function Reveal.arrived(self: any)
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
	local tiers = self.reply.tiers
	local before = if i == 1 then "Mystery" else tiers[i - 1]
	local after = tiers[i]
	self.phase = "Press"
	self.hint.Visible = false
	local side = self.side
	local reduced = UIAnim.reduced()
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
	if before == after then
		-- Kept: a squash, a small hop and a rattle.
		local K = R.Keep
		self.anim = {
			seconds = K.Seconds,
			step = function(t: number)
				local s = clamp01(t * K.Seconds / P.SquashSeconds)
				self.pose.scale = if t * K.Seconds < P.SquashSeconds
					then lerp(1, P.Squash, s)
					else lerp(
						P.Squash,
						1,
						backOut(clamp01((t * K.Seconds - P.SquashSeconds) / 0.2))
					)
				if not reduced then
					self.pose.lift = side * K.HopShare * math.sin(math.pi * t)
					self.pose.turn = P.ShakeDegrees * math.sin(t * 38) * (1 - t)
				end
			end,
			done = function()
				self.pose.scale, self.pose.lift, self.pose.turn = 1, 0, 0
				finish()
			end,
		}
		return
	end
	-- Changed: squash, bounces with a growing rattle, then the impact (flash, shake, burst)
	-- as the picture becomes the new block, which lands a little big and settles.
	local U = R.Upgrade
	local first = before == "Mystery"
	local hops = if first then U.FirstHopCount else U.HopCount
	local bounce = if first then U.FirstSeconds else U.Seconds
	local seconds = P.SquashSeconds + bounce
	self.anim = {
		seconds = seconds,
		step = function(t: number)
			local now = t * seconds
			if now < P.SquashSeconds then
				self.pose.scale = lerp(1, P.Squash, now / P.SquashSeconds)
				return
			end
			local q = clamp01((now - P.SquashSeconds) / bounce)
			self.pose.scale = lerp(P.Squash, 1, quadOut(clamp01(q * 4)))
			if reduced then
				return
			end
			local hop = math.abs(math.sin(math.pi * hops * q))
			self.pose.lift = side * U.HopShare * hop * (1 - q * 0.5)
			self.pose.turn = U.RattleDegrees * q * math.sin(q * 70)
		end,
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
	-- A white glow bursting from the block, then the tier's colour from the burst.
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
	if not UIAnim.reduced() then
		self.shakeAt = self.clock
	end
end

function Reveal.done(self: any)
	self.phase = "Done"
	if self.dotPulse then
		self.dotPulse.stop()
		self.dotPulse = nil
	end
	self.buffered = 0
	self.collectAt = os.clock() + R.DoneHintDelay
	local id = self.id
	task.delay(R.DoneHintDelay, function()
		if self.open and self.phase == "Done" and self.id == id then
			self.hint.Text = hint(true)
			self.hint.Visible = true
			UIAnim.popIn(self.hint)
			self.hintPulse = UIAnim.pulse(self.hint)
		end
	end)
	task.delay(R.AutoCollect, function()
		if self.open and self.phase == "Done" and self.id == id then
			self:leave()
		end
	end)
end

-- The jump back into the hotbar (or, after a refusal, the Mystery block going back as it was).
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
	for _, object in { self.title, self.label, self.hint } do
		UIAnim.popOut(object)
	end
	for _, d in self.dots do
		UIAnim.popOut(d.frame)
	end
	TweenService:Create(self.glow, fade, { ImageTransparency = 1 }):Play()
	TweenService:Create(self.rays, fade, { ImageTransparency = 1 }):Play()
	TweenService:Create(self.wash, fade, { BackgroundTransparency = 1 }):Play()
	local id = self.id
	local kind = if self.reply and not self.failed then self.reply.kind else "Mystery"
	-- The hotbar comes back a frame or two later (Progression sees isOpen go false): the slot
	-- is looked up every frame of the flight, until it is there.
	local inset = GuiService:GetGuiInset()
	local side, _, size = self:metrics()
	local target = Vector2.new(size.X / 2, size.Y + side)
	local endScale = 0.25
	local aimed = false
	local from = self.pose.at
	local fromScale = self.pose.scale
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
			self.pose.turn = L.ToTurn * math.sin(math.pi * t)
			self.pose.lift = 0
		end,
		done = function()
			self:finish(id, kind)
		end,
	}
end

-- Gone: the slot shows its block again and bounces.
function Reveal.finish(self: any, id: number, kind: string)
	if not self.open then
		return
	end
	self.open = false
	self.phase = "Closed"
	ContextActionService:UnbindAction(ACTION)
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
	self.deps.landed(id, kind)
end

--- Closes at once (a match is starting): the block is already its tier in the save.
function Reveal.close(self: any)
	if self.open then
		local kind = if self.reply and not self.failed then self.reply.kind else "Mystery"
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
	-- Floating while nothing else moves it (it keeps its clock, so it never jumps).
	local floatY, floatTurn = 0, 0
	if not reduced and (self.phase == "Wait" or self.phase == "Done") then
		self.floatClock += dt
		local F = R.Float
		local w = 2 * math.pi * self.floatClock / F.Seconds
		floatY = math.sin(w) * self.side * F.HeightShare
		floatTurn = math.sin(w * 0.5) * F.Degrees
	end
	local side = self.side
	local s = pose.scale
	self.holder.Position = UDim2.fromOffset(pose.at.X, pose.at.Y - pose.lift + floatY)
	self.holder.Size = UDim2.fromOffset(side, side)
	self.holderScale.Scale = math.max(0.01, s)
	self.holder.Rotation = pose.turn + floatTurn
	if not reduced then
		self.rays.Rotation = (self.rays.Rotation + R.RaysDegreesPerSecond * dt) % 360
	end
	-- The impact's screen shake: the whole screen jolts, fading out.
	local S = R.Shake
	local since = if self.shakeAt then self.clock - self.shakeAt else math.huge
	if since < S.Seconds then
		local fade = 1 - since / S.Seconds
		local px = side * S.Share * fade
		self.root.Position =
			UDim2.fromOffset(px * math.sin(since * S.Speed), px * math.cos(since * S.Speed * 1.3))
	elseif self.shakeAt then
		self.shakeAt = nil
		self.root.Position = UDim2.new()
	end
	self:stepParticles(dt, self.clock)
end

return Reveal
