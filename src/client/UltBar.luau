--!strict
-- UltBar: the ult bar's look (reference assets/ui/reference/08-ult-bar.webp in the house style,
-- UI_STYLE section 11), drawn by UltHud, which decides what it shows and when. Left to right:
-- the 8-ball badge with its blue splash over the pill's left end, "ULTIMATE" in outlined white
-- above, a thick ink-outlined pill with a blue fill and a moving shine, the % centred. A gain
-- flashes the fill's edge, bounces the badge and floats a "+34" (gold for a nice shot).
--
-- Ready: the fill turns gold with "READY! 100%", the gold badge, sparkles, a soft pulsing glow
-- behind it and a shake every ~2 s; a white pill above says how to activate it (PRESS [G] TO
-- ACTIVATE with a little keycap, TAP TO ACTIVATE, or PRESS [glyph] TO ACTIVATE with Roblox's
-- own button picture). The prompt stands where "ULTIMATE" was.
--
-- Laid out in pixels from Config.UI.Ults (a phone's or a computer's sizes); every loop runs
-- from step(), which UltHud calls each frame. The art (Config.UI.Kit.Icons.UltBadge and
-- UltBadgeGold, Kit.Art.Spark and SoftGlow) may still be "" while it uploads: the badge then
-- draws the kit's HUD 8 ball on a round splash, the sparkles use the rank badges' twinkle and
-- the glow is a soft rounded frame alone.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local HudParts = require(script.Parent.HudParts)
local UIAnim = require(script.Parent.UIAnim)

local U = Config.UI.Ults
local K = Config.UI.Kit
local Copy = Strings.Ults.Hud
local color = HudParts.color
local tone = HudParts.tone
local FONT: Enum.Font = (Enum.Font :: any)[K.Font]

local UltBar = {}
UltBar.__index = UltBar

--- The sizes for one screen (Config.UI.Ults pairs: a phone's, then a computer's).
export type Sizes = {
	width: number,
	pill: number,
	ball: number,
	label: number,
	percent: number,
	gap: number,
	prompt: number,
	promptText: number,
	float: number,
	floatRise: number,
	flash: number,
	sparkle: number,
	sparkleReach: number,
}

local function pick(pair: { number }, short: boolean): number
	return if short then pair[1] else pair[2]
end

--- The bar's sizes for a screen `short` or not, never wider than MaxWidthShare of `screenWidth`.
function UltBar.sizes(short: boolean, screenWidth: number): Sizes
	return {
		width = math.floor(math.min(pick(U.WidthPx, short), screenWidth * U.MaxWidthShare)),
		pill = pick(U.PillPx, short),
		ball = pick(U.BallPx, short),
		label = pick(U.LabelPx, short),
		percent = pick(U.PercentPx, short),
		gap = pick(U.GapPx, short),
		prompt = pick(U.PromptPx, short),
		promptText = pick(U.PromptTextPx, short),
		float = pick(U.FloatTextPx, short),
		floatRise = pick(U.FloatRisePx, short),
		flash = pick(U.FlashWidthPx, short),
		sparkle = pick(U.SparklePx, short),
		sparkleReach = pick(U.SparkleReachPx, short),
	}
end

--- Where the parts sit for `s`, in the bar's own pixels (0, 0 = the top left of "ULTIMATE"'s
--- row; the ball's left edge is x 0). Pure, so the layout can be checked by hand for any
--- screen: `height` is the whole footprint (the ball may hang below the pill).
function UltBar.geometry(s: Sizes): any
	local pillTop = s.label + s.gap
	local pillLeft = math.floor(s.ball * U.PillFromBallShare)
	local centreY = pillTop + s.pill / 2
	local overhang = math.max(0, (s.ball - s.pill) / 2)
	return {
		pillTop = pillTop,
		pillLeft = pillLeft,
		pillWidth = s.width - pillLeft,
		ballCentre = Vector2.new(s.ball / 2, centreY),
		covered = s.ball - pillLeft, -- the pill's part under the ball
		height = math.ceil(pillTop + s.pill + overhang),
		promptTop = pillTop - s.gap - s.prompt,
	}
end

-- A rounded frame with an ink outline.
local function inked(parent: Instance, name: string, strokePx: number): Frame
	local object = HudParts.frame(parent, name)
	object.BackgroundTransparency = 0
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = object
	local edge = Instance.new("UIStroke")
	edge.Name = "Edge"
	edge.Color = tone("Ink")
	edge.Thickness = strokePx
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = object
	return object
end

local function gradient(parent: Instance, pair: { { number } }): UIGradient
	local object = Instance.new("UIGradient")
	object.Rotation = 90
	object.Color = ColorSequence.new(color(pair[1]), color(pair[2]))
	object.Parent = parent
	return object
end

local function artOrNil(id: string?): string?
	return if type(id) == "string" and id ~= "" then id else nil
end

--- The bar, built into `parent` (UltHud's canvas). Size it with layout() before showing it.
function UltBar.new(parent: Instance): any
	local self: any = setmetatable({}, UltBar)
	self.value = -1
	self.ready = false
	self.promptMode = nil :: string?
	self.promptPulse = nil :: UIAnim.Handle? -- the prompt breathes while it waits for a press
	self.floats = {} :: { any }
	self.sparkles = {} :: { any }
	self.flashAt = -math.huge
	self.shakeClock = 0
	self.shineClock = 0
	self.sparkleClock = 0
	self.glowClock = 0

	local root = HudParts.frame(parent, "UltBar")
	self.root = root
	-- Everything that shakes (UIAnim owns no Rotation here: the shake is ours).
	local shaker = HudParts.frame(root, "Shaker")
	shaker.Size = UDim2.fromScale(1, 1)
	self.shaker = shaker

	-- The soft glow behind the pill while ready: the art if it is in, and a rounded frame.
	local glowArt = Instance.new("ImageLabel")
	glowArt.Name = "GlowArt"
	glowArt.BackgroundTransparency = 1
	glowArt.Image = artOrNil(K.Art.SoftGlow) or ""
	glowArt.ImageColor3 = color(U.ReadyGlow)
	glowArt.ScaleType = Enum.ScaleType.Stretch
	glowArt.AnchorPoint = Vector2.new(0.5, 0.5)
	glowArt.Visible = false
	glowArt.ZIndex = 0
	glowArt.Parent = shaker
	self.glowArt = glowArt
	local glow = HudParts.frame(shaker, "Glow")
	glow.BackgroundTransparency = 1
	glow.BackgroundColor3 = color(U.ReadyGlow)
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Visible = false
	glow.ZIndex = 0
	local glowRound = Instance.new("UICorner")
	glowRound.CornerRadius = UDim.new(0.5, 0)
	glowRound.Parent = glow
	self.glow = glow

	-- The pill: the empty track, the fill with its shine, the flash at the fill's edge.
	local pill = inked(shaker, "Pill", U.PillStrokePx)
	pill.BackgroundColor3 = color(U.TrackColor)
	pill.ZIndex = 1
	self.pill = pill
	gradient(pill, U.TrackFade)
	local fill = HudParts.frame(pill, "Fill")
	fill.BackgroundTransparency = 0
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.ZIndex = 2
	local fillRound = Instance.new("UICorner")
	fillRound.CornerRadius = UDim.new(0.5, 0)
	fillRound.Parent = fill
	self.fill = fill
	self.fillGradient = gradient(fill, U.FillBlue)
	local shine = HudParts.frame(fill, "Shine")
	shine.Size = UDim2.fromScale(1, 1)
	shine.BackgroundTransparency = 0
	shine.BackgroundColor3 = Color3.new(1, 1, 1)
	shine.ZIndex = 3
	local shineRound = Instance.new("UICorner")
	shineRound.CornerRadius = UDim.new(0.5, 0)
	shineRound.Parent = shine
	local band = Instance.new("UIGradient")
	band.Rotation = U.ShineDegrees
	band.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.42, 1),
		NumberSequenceKeypoint.new(0.5, U.ShineTransparency),
		NumberSequenceKeypoint.new(0.58, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	band.Offset = Vector2.new(-1, 0)
	band.Parent = shine
	self.shineBand = band
	-- A soft white gloss over the fill's top half, as the reference's bubbly fill.
	local gloss = HudParts.frame(fill, "Gloss")
	gloss.BackgroundTransparency = 0
	gloss.BackgroundColor3 = Color3.new(1, 1, 1)
	gloss.ZIndex = 3
	local glossRound = Instance.new("UICorner")
	glossRound.CornerRadius = UDim.new(0.5, 0)
	glossRound.Parent = gloss
	local glossFade = Instance.new("UIGradient")
	glossFade.Rotation = 90
	glossFade.Transparency = NumberSequence.new(U.GlossTransparency, 1)
	glossFade.Parent = gloss
	self.gloss = gloss
	local flash = HudParts.frame(pill, "EdgeFlash")
	flash.BackgroundTransparency = 1
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.AnchorPoint = Vector2.new(0.5, 0)
	flash.ZIndex = 4
	local flashRound = Instance.new("UICorner")
	flashRound.CornerRadius = UDim.new(0.5, 0)
	flashRound.Parent = flash
	self.flash = flash
	local percent = HudParts.text(pill, "Percent", 18, "")
	percent.AutoLocalize = false -- a number, or READY! with a number, filled from Strings
	percent.TextWrapped = false
	percent.ZIndex = 5
	self.percent = percent

	-- ULTIMATE above the pill.
	local label = HudParts.text(shaker, "Title", 16, Copy.Title)
	label.TextWrapped = false
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 5
	self.label = label

	-- The badge: the art, or the kit's HUD 8 ball on a round splash. It bounces on a gain.
	local badge = HudParts.frame(shaker, "Badge")
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.ZIndex = 6
	self.badge = badge
	local art = Instance.new("ImageLabel")
	art.Name = "Art"
	art.BackgroundTransparency = 1
	art.ScaleType = Enum.ScaleType.Fit
	art.ZIndex = 2
	art.Parent = badge
	self.art = art
	local splash = inked(badge, "Splash", U.PillStrokePx - 0.5)
	splash.BackgroundColor3 = color(U.SplashBlue)
	splash.AnchorPoint = Vector2.new(0.5, 0.5)
	splash.ZIndex = 1
	self.splash = splash
	local ball = HudParts.ball(badge)
	ball.root.AnchorPoint = Vector2.new(0.5, 0.5)
	ball.root.Position = UDim2.fromScale(0.5, 0.5)
	ball.root.ZIndex = 3
	HudParts.paintBall(ball, 8, false)
	self.ball = ball

	-- The prompt over the pill: words, then a keycap or a glyph, then words.
	local prompt = HudParts.pill(root, "Prompt")
	prompt.AnchorPoint = Vector2.new(0.5, 0)
	prompt.Visible = false
	prompt.ZIndex = 7
	self.prompt = prompt
	local before = HudParts.text(prompt, "Before", 16, "", tone("Ink"))
	before.TextWrapped = false
	before.ZIndex = 8
	local outline = before:FindFirstChild("Outline")
	if outline then
		outline:Destroy() -- ink words on the white pill (UI_STYLE 3: small text, no outline)
	end
	local after = before:Clone()
	after.Name = "After"
	after.Parent = prompt
	self.before, self.after = before, after
	local keycap = inked(prompt, "Keycap", 2)
	keycap.BackgroundColor3 = Color3.new(1, 1, 1)
	keycap.ZIndex = 8
	local keycapRound = keycap:FindFirstChildOfClass("UICorner")
	if keycapRound then
		keycapRound.CornerRadius = UDim.new(0, U.KeycapCornerPx)
	end
	local keyLetter = Instance.new("TextLabel")
	keyLetter.Name = "Key"
	keyLetter.BackgroundTransparency = 1
	keyLetter.Font = FONT
	keyLetter.TextColor3 = tone("Ink")
	keyLetter.Text = U.KeyboardKey
	keyLetter.AutoLocalize = false -- the key's name as printed on the keyboard
	keyLetter.TextScaled = true
	keyLetter.Size = UDim2.fromScale(1, 1)
	keyLetter.ZIndex = 9
	keyLetter.Parent = keycap
	self.keycap = keycap
	local glyph = Instance.new("ImageLabel")
	glyph.Name = "Glyph"
	glyph.BackgroundTransparency = 1
	glyph.ScaleType = Enum.ScaleType.Fit
	glyph.ZIndex = 8
	glyph.Parent = prompt
	self.glyph = glyph

	self:setArt()
	return self
end

-- The badge's picture: the art (gold while ready) or the drawn fallback.
function UltBar.setArt(self: any)
	local id = artOrNil(if self.ready then K.Icons.UltBadgeGold else K.Icons.UltBadge)
		or artOrNil(K.Icons.UltBadge)
	self.art.Image = id or ""
	self.art.Visible = id ~= nil
	self.splash.Visible = id == nil
	self.ball.root.Visible = id == nil
	self.splash.BackgroundColor3 = color(if self.ready then U.SplashGold else U.SplashBlue)
end

--- Lay the bar out for `s` (UltBar.sizes). Returns its geometry.
function UltBar.layout(self: any, s: Sizes): any
	self.sizes = s
	local g = UltBar.geometry(s)
	self.geo = g
	self.root.Size = UDim2.fromOffset(s.width, g.height)
	local pill = self.pill
	pill.Position = UDim2.fromOffset(g.pillLeft, g.pillTop)
	pill.Size = UDim2.fromOffset(g.pillWidth, s.pill)
	-- The glow reaches past the pill all round.
	local reach = s.pill * U.GlowReachShare
	local centre = Vector2.new(g.pillLeft + g.pillWidth / 2, g.pillTop + s.pill / 2)
	self.glow.Position = UDim2.fromOffset(centre.X, centre.Y)
	self.glow.Size = UDim2.fromOffset(g.pillWidth + reach * 2, s.pill + reach * 2)
	self.glowArt.Position = self.glow.Position
	self.glowArt.Size = UDim2.fromOffset(g.pillWidth + reach * 5, s.pill + reach * 5)
	-- The % centred on the pill's visible part (right of the ball).
	HudParts.setTextSize(self.percent, s.percent)
	self.percent.Position = UDim2.fromOffset(g.covered, 1)
	self.percent.Size = UDim2.fromOffset(math.max(1, g.pillWidth - g.covered - 4), s.pill - 2)
	HudParts.setTextSize(self.label, s.label)
	self.label.Position = UDim2.fromOffset(s.ball + 2, 0)
	self.label.Size = UDim2.fromOffset(math.max(1, s.width - s.ball - 2), s.label + s.gap)
	self.flash.Size = UDim2.fromOffset(s.flash, s.pill)
	-- The badge: a square round the ball's centre; the art is placed so ITS ball lands there.
	local badge = self.badge
	local size = s.ball / (2 * U.BadgeBall.Radius)
	badge.Position = UDim2.fromOffset(g.ballCentre.X, g.ballCentre.Y)
	badge.Size = UDim2.fromOffset(s.ball, s.ball)
	self.art.Size = UDim2.fromOffset(size, size)
	self.art.Position =
		UDim2.fromOffset(s.ball / 2 - U.BadgeBall.X * size, s.ball / 2 - U.BadgeBall.Y * size)
	local splash = s.ball * U.SplashShare
	self.splash.Size = UDim2.fromOffset(splash, splash)
	self.splash.Position =
		UDim2.new(0.5, -s.ball * U.SplashOffsetShare, 0.5, -s.ball * U.SplashOffsetShare)
	HudParts.sizeBall(self.ball, s.ball)
	self:setValue(math.max(0, self.value))
	self:layoutPrompt()
	return g
end

--- Show `value` (0..BarMax) in the fill and the %.
function UltBar.setValue(self: any, value: number)
	local s, g = self.sizes, self.geo
	self.value = value
	if not s then
		return
	end
	local share = math.clamp(value / Config.Ults.BarMax, 0, 1)
	local visible = g.pillWidth - g.covered
	local width = g.covered + visible * share
	self.fill.Size = UDim2.fromOffset(width, s.pill)
	self.fill.Visible = width > 0.5
	self.gloss.Position = UDim2.fromOffset(s.pill * 0.25, 2)
	self.gloss.Size = UDim2.fromOffset(math.max(0, width - s.pill * 0.5), s.pill * 0.42)
	self.flash.Position = UDim2.fromOffset(width, 0)
	local whole = math.floor(value + 0.5)
	self.percent.Text = if self.ready then Copy.Ready:format(whole) else Copy.Percent:format(whole)
end

--- The ready look on or off: the gold fill and badge, READY!, the glow (sparkles and the shake
--- run from step while it is on).
function UltBar.setReady(self: any, ready: boolean)
	if self.ready == ready then
		return
	end
	self.ready = ready
	self.fillGradient.Color = ColorSequence.new(
		color(if ready then U.FillGold[1] else U.FillBlue[1]),
		color(if ready then U.FillGold[2] else U.FillBlue[2])
	)
	self.glow.Visible = ready
	self.glowArt.Visible = ready and self.glowArt.Image ~= ""
	self.shakeClock = U.ShakeEverySeconds - U.ShakeFirstSeconds -- the first shake comes soon
	self:setArt()
	self:setValue(self.value)
	if ready then
		UIAnim.bounce(self.badge)
	end
end

--- How to activate, above the bar: "key" (the keycap), "pad" (the controller's glyph `image`),
--- "tap", or nil for none (ULTIMATE shows instead). `dim` greys it while a press is on its way;
--- otherwise it breathes (Config.UI.Ults PromptPulseScale, the designer 2026-10-09: "a bit bigger
--- and noticeable").
function UltBar.setPrompt(self: any, mode: string?, image: string?, dim: boolean?)
	self.promptMode = mode
	self.prompt.Visible = mode ~= nil
	self.label.Visible = mode == nil
	local breathe = mode ~= nil and not dim
	if breathe and self.promptPulse == nil then
		self.promptPulse = UIAnim.pulse(self.prompt, U.PromptPulseScale, U.PromptPulseSeconds)
	elseif not breathe and self.promptPulse then
		self.promptPulse.stop()
		self.promptPulse = nil
	end
	if mode == nil then
		return
	end
	local copy = if mode == "tap" then Copy.Tap else Copy.PressKey
	local at = string.find(copy, "%s", 1, true)
	self.before.Text = if at then string.sub(copy, 1, at - 1) else copy
	self.after.Text = if at then string.sub(copy, at + 2) else ""
	self.keycap.Visible = mode == "key"
	self.glyph.Visible = mode == "pad"
	self.glyph.Image = image or ""
	local fade = if dim then U.PromptDimTransparency else 0
	self.prompt.BackgroundTransparency = fade
	self.before.TextTransparency = fade
	self.after.TextTransparency = fade
	self:layoutPrompt()
end

-- The prompt's words and key, side by side, centred over the pill.
function UltBar.layoutPrompt(self: any)
	local s, g = self.sizes, self.geo
	if not s or self.promptMode == nil then
		return
	end
	local height = s.prompt
	local text = s.promptText
	local key = math.floor(height * U.KeycapShare)
	local pad = math.floor(height * 0.45)
	local spacer = math.floor(text * 0.3)
	local function width(words: string): number
		if words == "" then
			return 0
		end
		return math.ceil(TextService:GetTextSize(words, text, FONT, Vector2.new(2000, 200)).X) + 2
	end
	local hasKey = self.promptMode ~= "tap"
	local beforeWidth = width(self.before.Text)
	local afterWidth = width(self.after.Text)
	local total = pad * 2 + beforeWidth + afterWidth + (if hasKey then key + spacer * 2 else 0)
	self.prompt.Size = UDim2.fromOffset(total, height)
	self.prompt.Position = UDim2.fromOffset(g.pillLeft + g.pillWidth / 2, g.promptTop)
	local x = pad
	for _, words in { self.before, self.after } do
		HudParts.setTextSize(words, text)
	end
	self.before.Position = UDim2.fromOffset(x, 0)
	self.before.Size = UDim2.fromOffset(math.max(1, beforeWidth), height)
	x += beforeWidth
	if hasKey then
		x += spacer
		for _, object in { self.keycap, self.glyph } do
			object.Position = UDim2.fromOffset(x, (height - key) / 2)
			object.Size = UDim2.fromOffset(key, key)
		end
		x += key + spacer
	end
	self.after.Position = UDim2.fromOffset(x, 0)
	self.after.Size = UDim2.fromOffset(math.max(1, afterWidth), height)
end

--- A gain: the edge flashes, the badge bounces and "+34" floats up from the fill's edge (gold
--- for a nice shot).
function UltBar.gain(self: any, amount: number, nice: boolean)
	local s, g = self.sizes, self.geo
	if not s then
		return
	end
	self.flashAt = os.clock()
	UIAnim.bounce(self.badge)
	local words = HudParts.text(
		self.root,
		"Gain",
		s.float,
		Copy.Gain:format(math.floor(amount + 0.5)),
		if nice then tone("Gold") else tone("White")
	)
	words.AutoLocalize = false
	words.TextWrapped = false
	words.AnchorPoint = Vector2.new(0.5, 1)
	words.Size = UDim2.fromOffset(s.float * 4, s.float + 4)
	words.ZIndex = 10
	local edge = self.fill.Size.X.Offset
	local x = math.clamp(g.pillLeft + edge, g.pillLeft + s.float * 2, g.pillLeft + g.pillWidth)
	table.insert(self.floats, {
		label = words,
		x = x,
		y = g.pillTop - 2,
		startedAt = os.clock(),
	})
end

-- One twinkle somewhere on the pill's outline.
function UltBar.sparkle(self: any, random: Random)
	local s, g = self.sizes, self.geo
	local image = artOrNil(K.Art.Spark) or artOrNil(Config.UI.Ranks.Sparkle)
	if not s or not image then
		return
	end
	local star = Instance.new("ImageLabel")
	star.Name = "Sparkle"
	star.BackgroundTransparency = 1
	star.Image = image
	star.ImageColor3 = color(U.SparkleColor)
	star.AnchorPoint = Vector2.new(0.5, 0.5)
	star.ZIndex = 9
	local side = random:NextNumber()
	local x = g.pillLeft + random:NextNumber(0.05, 1) * g.pillWidth
	local reach = random:NextNumber(0.3, 1) * s.sparkleReach
	local y = if side < 0.5 then g.pillTop - reach else g.pillTop + s.pill + reach
	if random:NextNumber() < 0.2 then
		-- Now and then off the pill's right end instead.
		x = g.pillLeft + g.pillWidth + reach
		y = g.pillTop + random:NextNumber(0, 1) * s.pill
	end
	star.Position = UDim2.fromOffset(x, y)
	star.Rotation = random:NextNumber(0, 90)
	star.Parent = self.root
	table.insert(
		self.sparkles,
		{ image = star, startedAt = os.clock(), spin = random:NextNumber(-90, 90) }
	)
end

--- Every frame while shown: the shine, the edge flash, the floats, and while ready the glow,
--- the sparkles and the shake.
function UltBar.step(self: any, dt: number, random: Random)
	local now = os.clock()
	local s = self.sizes
	if not s then
		return
	end
	-- The shine: a pass along the fill, then a pause.
	self.shineClock = (self.shineClock + dt) % (U.ShineSeconds + U.ShinePauseSeconds)
	local t = math.clamp(self.shineClock / U.ShineSeconds, 0, 1)
	self.shineBand.Offset = Vector2.new(-1 + 2 * t, 0)
	-- The flash at the fill's edge.
	local flashT = (now - self.flashAt) / U.FlashSeconds
	self.flash.BackgroundTransparency = if flashT >= 0 and flashT < 1 then flashT else 1
	-- The floating numbers: up and fading.
	for i = #self.floats, 1, -1 do
		local f = self.floats[i]
		local k = (now - f.startedAt) / U.FloatSeconds
		if k >= 1 then
			f.label:Destroy()
			table.remove(self.floats, i)
		else
			local rise = UIAnim.quadOut(k) * s.floatRise
			f.label.Position = UDim2.fromOffset(f.x, f.y - rise)
			local fade = math.clamp((k - U.FloatFadeFrom) / (1 - U.FloatFadeFrom), 0, 1)
			HudParts.setTextTransparency(f.label, fade)
			local pop = UIAnim.backOut(math.min(1, k / 0.25))
			f.label.Rotation = 0
			f.label.Size = UDim2.fromOffset(s.float * 4, (s.float + 4) * (0.6 + 0.4 * pop))
		end
	end
	-- Sparkles: grow, turn and fade.
	for i = #self.sparkles, 1, -1 do
		local p = self.sparkles[i]
		local k = (now - p.startedAt) / U.SparkleSeconds
		if k >= 1 then
			p.image:Destroy()
			table.remove(self.sparkles, i)
		else
			local size = s.sparkle * math.sin(k * math.pi)
			p.image.Size = UDim2.fromOffset(size, size)
			p.image.Rotation += p.spin * dt
			p.image.ImageTransparency = math.clamp((k - 0.6) / 0.4, 0, 1)
		end
	end
	if not self.ready then
		self.shaker.Rotation = 0
		self.shaker.Position = UDim2.fromOffset(0, 0)
		return
	end
	-- The soft glow breathes.
	self.glowClock += dt
	local breath = 0.5 + 0.5 * math.sin(self.glowClock / U.GlowPulseSeconds * 2 * math.pi)
	local low, high = U.GlowTransparency[1], U.GlowTransparency[2]
	self.glow.BackgroundTransparency = high + (low - high) * breath
	self.glowArt.ImageTransparency = high + (low - high) * breath
	-- Sparkles pop now and then.
	self.sparkleClock += dt
	if self.sparkleClock >= U.SparkleEverySeconds then
		self.sparkleClock = 0
		self:sparkle(random)
	end
	-- A shake every ShakeEverySeconds, to invite the press: a quick damped wobble.
	self.shakeClock += dt
	if self.shakeClock >= U.ShakeEverySeconds then
		self.shakeClock -= U.ShakeEverySeconds
	end
	local k = self.shakeClock / U.ShakeSeconds
	if k < 1 then
		local damp = 1 - k
		local wave = math.sin(k * U.ShakeWobbles * 2 * math.pi)
		self.shaker.Rotation = U.ShakeDegrees * wave * damp
		self.shaker.Position = UDim2.fromOffset(U.ShakePx * wave * damp, 0)
	else
		self.shaker.Rotation = 0
		self.shaker.Position = UDim2.fromOffset(0, 0)
	end
end

--- Drop the floats and sparkles (the bar hid).
function UltBar.clearEffects(self: any)
	for _, f in self.floats do
		f.label:Destroy()
	end
	table.clear(self.floats)
	for _, p in self.sparkles do
		p.image:Destroy()
	end
	table.clear(self.sparkles)
	self.shaker.Rotation = 0
	self.shaker.Position = UDim2.fromOffset(0, 0)
end

return UltBar
