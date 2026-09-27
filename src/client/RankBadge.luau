--!strict
-- RankBadge: the one rank badge every screen shows (the rank HUD, nameplates, the match bar,
-- the result screen, NEW RANK! and the roadmap). The rank's badge image (Config.UI.Ranks) that
-- shines as assets/ui/ranks/README.md describes (UI_STYLE section 7), more as you climb:
-- - Bronze to Diamond: a light sweep, the shine band of UIAnim.shine clipped to the badge's
--   own shape (a white shine mask of it with a UIGradient whose Offset crosses from -1 to 1);
-- - Expert to Grandmaster: the sweep plus sparkles twinkling one after another;
-- - Reyes: a quicker sweep, more sparkles and gold rays turning behind it;
-- - Unranked: still.
--
-- Every live badge is driven by ONE shared clock: a single RenderStepped connection made when
-- the first badge is made and dropped when the last one is destroyed. Each badge has its own
-- phase, so a screen full of them does not flash together. A badge whose root is destroyed
-- leaves the clock by itself. Tiny badges skip the sparkles and rays (specks on screen).
--
-- An interactive badge is an ImageButton (selectable, for a gamepad): the mouse or a gamepad
-- selection pops it up with a quicker, brighter sweep; a tap, click or A squishes and bounces it,
-- then runs its action. Hover and press use the badge's own UIScale ("PressScale"); pops and
-- bursts use UIAnim's "AnimScale" on an inner frame. So a screen may still UIAnim the root.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Ranks = require(Shared:WaitForChild("Progression"):WaitForChild("Ranks"))
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local R = Config.UI.Ranks
local BADGES: { [string]: string } = R.Badges :: any
local MASKS: { [string]: string } = R.Masks :: any
local SPOTS: { { number } } = R.SparkleSpots
local TOP_TIER = #Config.Ranks.Tiers
local HIGH_FROM = Ranks.tierIndex(R.HighShineFrom) or TOP_TIER
local QUICK = Config.Multiplayer.Style.QuickMotion
-- Spreads the badges' phases evenly over a cycle however many there are (the golden ratio).
local PHASE_STEP = 0.6180339887
local TAU = 2 * math.pi

export type Options = {
	size: number, -- pixels, square
	interactive: boolean?, -- reacts to hover and press (default false)
	onPress: (() -> ())?, -- called after the press bounce starts (interactive only)
	shine: boolean?, -- default true; false = a still image (a locked roadmap stop)
	name: string?,
	zIndex: number?,
	-- Extra: false keeps Reyes' rays off even when big, for a badge beside words (the rank
	-- HUD's pill, a nameplate's name), which the rays would otherwise cover. Default true.
	rays: boolean?,
}

export type Badge = {
	root: GuiObject, -- a square Frame (an ImageButton when interactive) to position
	button: GuiButton?, -- the button when interactive (Selectable, for gamepad selection)
	set: (self: Badge, tier: string, division: number, pop: boolean?) -> (),
	setSize: (self: Badge, px: number) -> (),
	setShining: (self: Badge, on: boolean) -> (),
	burst: (self: Badge) -> (),
	destroy: (self: Badge) -> (),
	-- Extras: press and hover it from another control (the rank HUD's pill), fade it.
	press: (self: Badge) -> (),
	hover: (self: Badge, on: boolean) -> (),
	setTransparency: (self: Badge, transparency: number) -> (),
}

-- One tier band's shine (Config.UI.Ranks.Shine.Low, High or Top).
type Band = {
	Every: number,
	Across: number,
	Sparkles: number,
	SparkleCycle: number,
	RaysSeconds: number?,
}

local RankBadge = {}
local Badge = {}
Badge.__index = Badge

local function bandFor(tier: string): Band?
	local index = Ranks.tierIndex(tier)
	if index == nil or index == 0 then
		return nil -- Unranked (or an unknown name) is still
	end
	local shine: any = R.Shine
	if index >= TOP_TIER then
		return shine.Top
	elseif index >= HIGH_FROM then
		return shine.High
	end
	return shine.Low
end

-- The sweep's band: clear everywhere but a narrow band in the middle, `peak` at its brightest.
local function bandCurve(peak: number): NumberSequence
	local half = R.ShineBandWidth
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5 - half, 1),
		NumberSequenceKeypoint.new(0.5, peak),
		NumberSequenceKeypoint.new(0.5 + half, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
end

local NORMAL_BAND = bandCurve(R.ShineBandTransparency)
local BRIGHT_BAND = bandCurve(R.ShineBrightTransparency)

local function quadInOut(t: number): number
	if t < 0.5 then
		return 2 * t * t
	end
	local u = -2 * t + 2
	return 1 - u * u / 2
end

local function frame(parent: Instance, name: string, zIndex: number): Frame
	local object = Instance.new("Frame")
	object.Name = name
	object.BackgroundTransparency = 1
	object.BorderSizePixel = 0
	object.AnchorPoint = Vector2.new(0.5, 0.5)
	object.Position = UDim2.fromScale(0.5, 0.5)
	object.Size = UDim2.fromScale(1, 1)
	object.ZIndex = zIndex
	object.Parent = parent
	return object
end

local function image(parent: Instance, name: string, id: string, zIndex: number): ImageLabel
	local object = Instance.new("ImageLabel")
	object.Name = name
	object.BackgroundTransparency = 1
	object.BorderSizePixel = 0
	object.ScaleType = Enum.ScaleType.Fit
	object.Image = id
	object.AnchorPoint = Vector2.new(0.5, 0.5)
	object.Position = UDim2.fromScale(0.5, 0.5)
	object.Size = UDim2.fromScale(1, 1)
	object.ZIndex = zIndex
	object.Parent = parent
	return object
end

--------------------------------------------------------------------------------------------
-- The shared clock
--------------------------------------------------------------------------------------------

local live: { [any]: boolean } = {}
local clock: RBXScriptConnection? = nil
local made = 0 -- badges made so far, for their phases

local step: (any, number) -> ()

local function tick()
	local now = os.clock()
	for badge in live do
		step(badge, now)
	end
end

local function join(badge: any)
	live[badge] = true
	if clock == nil then
		clock = RunService.RenderStepped:Connect(tick)
	end
end

local function leave(badge: any)
	live[badge] = nil
	if next(live) == nil and clock then
		clock:Disconnect()
		clock = nil
	end
end

-- Start a sweep now (a pop, a press, a hover, or the next idle one). `bright` makes it the
-- brighter band.
local function beginSweep(self: any, now: number, bright: boolean)
	local band: Band? = self.band
	local every = if self.hovered
		then R.HoverShineEvery
		elseif band then band.Every
		else R.HoverShineEvery
	local across = if band then band.Across else R.Shine.Low.Across
	self.sweepStart = now
	self.sweepAcross = math.min(across, every * 0.75)
	self.nextSweep = now + every
	if self.bright ~= bright then
		self.bright = bright
		self.gradient.Transparency = if bright then BRIGHT_BAND else NORMAL_BAND
	end
end

local function hideAll(list: { ImageLabel })
	for _, object in list do
		if object.Visible then
			object.Visible = false
		end
	end
end

step = function(self: any, now: number)
	local root: GuiObject = self.root
	if not root.Visible or root.Parent == nil then
		return
	end
	local band: Band? = self.band
	local lively = self.shining and band ~= nil
	-- The sweep: the idle one every Every seconds (quicker while hovered), plus forced ones.
	if self.sweepStart == nil and (lively or self.hovered) and now >= self.nextSweep then
		beginSweep(self, now, self.hovered)
	end
	local offset = -1
	if self.sweepStart ~= nil then
		local t = (now - self.sweepStart) / self.sweepAcross
		if t >= 1 then
			self.sweepStart = nil
		else
			offset = -1 + 2 * quadInOut(t)
		end
	end
	if offset ~= self.offset then
		self.offset = offset
		self.gradient.Offset = Vector2.new(offset, 0)
	end
	-- Sparkles and rays only where they read: a shining badge big enough on screen.
	local px = 0
	if
		lively
		and band
		and (band.Sparkles > 0 or (self.raysAllowed and band.RaysSeconds ~= nil))
	then
		px = root.AbsoluteSize.X
	end
	local count = if lively and band and px >= R.SparkleMinPx then band.Sparkles else 0
	if count > 0 and band then
		-- Each twinkles in turn at one of the bright spots (as the preview): it grows from
		-- nothing and shrinks back, turning, over the first half of its cycle.
		local cycle = band.SparkleCycle
		for i, sparkle in self.sparkles do
			local shown = false
			if i <= count then
				local c = (now + (self.seed + (i - 1) / count) * cycle) / cycle
				local k = math.floor(c)
				local p = c - k
				if p < 0.5 then
					shown = true
					local spot = SPOTS[(k * 3 + (i - 1) * 5) % #SPOTS + 1]
					local size = math.sin(p * TAU) * R.SparkleShare
					sparkle.Position = UDim2.fromScale(spot[1], spot[2])
					sparkle.Size = UDim2.fromScale(size, size)
					sparkle.Rotation = math.deg(p * 1.5)
				end
			end
			if sparkle.Visible ~= shown then
				sparkle.Visible = shown
			end
		end
	elseif self.sparklesShown then
		hideAll(self.sparkles)
	end
	self.sparklesShown = count > 0
	local raysSeconds = if band and self.raysAllowed then band.RaysSeconds else nil
	local rays = lively and raysSeconds ~= nil and px >= R.RaysMinPx
	if self.rays.Visible ~= rays then
		self.rays.Visible = rays
	end
	if rays and raysSeconds then
		self.rays.Rotation = ((now / raysSeconds + self.seed) * 360) % 360
	end
	-- A burst's sparkles: one at every bright spot, one after another, once.
	local burstAt = self.burstAt
	if burstAt ~= nil then
		local running = false
		for i, sparkle in self.burstSparkles do
			local u = (now - burstAt - (i - 1) * R.BurstStaggerSeconds) / R.BurstSparkleSeconds
			local shown = u > 0 and u < 1
			if shown then
				local size = math.sin(u * math.pi) * R.BurstSparkleShare
				sparkle.Size = UDim2.fromScale(size, size)
				sparkle.Rotation = u * 90
			end
			running = running or u < 1
			if sparkle.Visible ~= shown then
				sparkle.Visible = shown
			end
		end
		if not running then
			self.burstAt = nil
			hideAll(self.burstSparkles)
		end
	end
end

--------------------------------------------------------------------------------------------
-- Badges
--------------------------------------------------------------------------------------------

local function isTouch(): boolean
	return UserInputService:GetLastInputType() == Enum.UserInputType.Touch
end

-- Stop a hover tween or press bounce on its way.
local function stopScale(self: any)
	self.pressToken += 1
	if self.pressTween then
		self.pressTween:Cancel()
		self.pressTween = nil
	end
end

-- Tween the hover and press scale to `target`.
local function scaleTo(self: any, target: number)
	stopScale(self)
	local tween = TweenService:Create(
		self.pressScale,
		TweenInfo.new(QUICK, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = target }
	)
	self.pressTween = tween
	tween:Play()
end

local function makeSparkle(self: any, name: string): ImageLabel
	local sparkle = image(self.body, name, R.Sparkle, self.z + 3)
	sparkle.Size = UDim2.fromScale(0, 0)
	sparkle.Visible = false
	sparkle.ImageTransparency = self.transparency
	return sparkle
end

--- A new badge in `parent`, showing Unranked until `set`. See the module header.
function RankBadge.new(parent: Instance, options: Options): Badge
	local self: any = setmetatable({}, Badge)
	local z = options.zIndex or 1
	made += 1
	self.z = z
	self.seed = (made * PHASE_STEP) % 1
	self.alive = true
	self.shining = options.shine ~= false
	self.raysAllowed = options.rays ~= false
	self.hovered = false
	self.band = nil
	self.key = nil
	self.offset = -1
	self.bright = false
	self.sweepStart = nil
	self.sweepAcross = 1
	self.burstAt = nil
	self.sparklesShown = false
	self.transparency = 0
	self.pressToken = 0
	self.pressTween = nil
	self.onPress = options.onPress
	self.connections = {}
	local root: GuiObject
	if options.interactive then
		local button = Instance.new("ImageButton")
		button.Image = ""
		button.AutoButtonColor = false
		button.Selectable = true
		-- The badge's own pop and sweep show selection; hide Roblox's default box.
		local noBox = Instance.new("Frame")
		noBox.BackgroundTransparency = 1
		button.SelectionImageObject = noBox
		root = button
		self.button = button
	else
		root = Instance.new("Frame")
		self.button = nil
	end
	root.Name = options.name or "RankBadge"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Size = UDim2.fromOffset(options.size, options.size)
	root.ZIndex = z
	self.root = root
	-- Hover and press scale the outer frame, pops and bursts the inner one (UIAnim).
	local press = frame(root, "Press", z)
	local pressScale = Instance.new("UIScale")
	pressScale.Name = "PressScale"
	pressScale.Parent = press
	self.pressScale = pressScale
	local body = frame(press, "Body", z)
	self.body = body
	-- Reyes' gold rays behind the badge, turning about the 8 ball.
	local rays = image(body, "Rays", Config.UI.Kit.Art.Rays, z)
	rays.ImageColor3 = Color3.fromRGB(R.RaysColor[1], R.RaysColor[2], R.RaysColor[3])
	rays.ImageTransparency = R.RaysTransparency
	rays.Position = UDim2.fromScale(R.RaysCenter[1], R.RaysCenter[2])
	rays.Size = UDim2.fromScale(R.RaysScale, R.RaysScale)
	rays.Visible = false
	self.rays = rays
	self.image = image(body, "Badge", "", z + 1)
	-- The sweep: the badge's shape in white, seen only where the band crosses it.
	local shine = image(body, "Shine", "", z + 2)
	shine.ImageColor3 = Color3.new(1, 1, 1)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = R.ShineRotation
	gradient.Transparency = NORMAL_BAND
	gradient.Offset = Vector2.new(-1, 0)
	gradient.Parent = shine
	self.shine = shine
	self.gradient = gradient
	self.sparkles = {}
	self.burstSparkles = {}
	self.nextSweep = os.clock() + self.seed * R.Shine.Low.Every
	if self.button then
		local button = self.button
		table.insert(
			self.connections,
			button.MouseEnter:Connect(function()
				if not isTouch() then
					self:hover(true)
				end
			end)
		)
		table.insert(
			self.connections,
			button.MouseLeave:Connect(function()
				self:hover(false)
			end)
		)
		table.insert(
			self.connections,
			button.SelectionGained:Connect(function()
				self:hover(true)
			end)
		)
		table.insert(
			self.connections,
			button.SelectionLost:Connect(function()
				self:hover(false)
			end)
		)
		table.insert(
			self.connections,
			button.Activated:Connect(function()
				self:press()
			end)
		)
	end
	table.insert(
		self.connections,
		root.Destroying:Connect(function()
			self:destroy()
		end)
	)
	self:set("Unranked", 0)
	root.Parent = parent
	join(self)
	return self :: Badge
end

--- Show a rank: its tier ("Gold", "Reyes", "Unranked") and division (1-5; 0 for Unranked).
--- `pop` bounces the badge with a bright sweep (a rank change seen live).
function Badge.set(self: any, tier: string, division: number, pop: boolean?)
	if not self.alive then
		return
	end
	local key = Ranks.badgeKey(tier, division)
	if key ~= self.key then
		self.key = key
		self.image.Image = BADGES[key] or BADGES.unranked or ""
		self.shine.Image = MASKS[key] or ""
	end
	local band = bandFor(tier)
	self.band = band
	if band then
		for i = #self.sparkles + 1, band.Sparkles do
			table.insert(self.sparkles, makeSparkle(self, "Sparkle" .. i))
		end
	end
	if pop then
		UIAnim.bounce(self.body)
		beginSweep(self, os.clock(), true)
	end
end

--- Size the badge in pixels (square). A screen may also size `root` itself (in scale).
function Badge.setSize(self: any, px: number)
	self.root.Size = UDim2.fromOffset(px, px)
end

--- Shine or not: far nameplates and locked roadmap stops turn it off (a still image).
function Badge.setShining(self: any, on: boolean)
	if self.shining == on then
		return
	end
	self.shining = on
	if on then
		local band: Band? = self.band
		self.nextSweep = os.clock() + self.seed * (if band then band.Every else 1)
	end
end

--- A big bright pop (a rank-up): the badge jumps up and settles, sweeps, and sparkles burst
--- at every bright spot, once.
function Badge.burst(self: any)
	if not self.alive then
		return
	end
	local now = os.clock()
	local scale = UIAnim.scaleOf(self.body)
	local grow = TweenService:Create(
		scale,
		TweenInfo.new(R.BurstGrowSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Scale = R.BurstScale }
	)
	grow.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed and self.alive then
			TweenService
				:Create(
					scale,
					TweenInfo.new(
						R.BurstSettleSeconds,
						Enum.EasingStyle.Back,
						Enum.EasingDirection.Out
					),
					{ Scale = 1 }
				)
				:Play()
		end
	end)
	grow:Play()
	beginSweep(self, now, true)
	for i = #self.burstSparkles + 1, #SPOTS do
		local sparkle = makeSparkle(self, "Burst" .. i)
		sparkle.Position = UDim2.fromScale(SPOTS[i][1], SPOTS[i][2])
		table.insert(self.burstSparkles, sparkle)
	end
	self.burstAt = now
end

--- The press: a squish and bounce through Config.UI.Ranks.PressScales, a click and a bright
--- sweep, then the badge's onPress. Taps, clicks and gamepad A come here by themselves; the
--- rank HUD's pill calls it too.
function Badge.press(self: any)
	if not self.alive then
		return
	end
	stopScale(self)
	local token = self.pressToken
	local rest = if self.hovered then R.HoverScale else 1
	local scales: { number } = R.PressScales
	local seconds = R.PressSeconds / #scales
	local index = 0
	local function nextStep()
		index += 1
		if token ~= self.pressToken or not self.alive or index > #scales then
			return
		end
		local tween = TweenService:Create(
			self.pressScale,
			TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Scale = scales[index] * rest }
		)
		self.pressTween = tween
		tween.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed then
				nextStep()
			end
		end)
		tween:Play()
	end
	nextStep()
	UISound.play("Click")
	beginSweep(self, os.clock(), true)
	local onPress = self.onPress
	if onPress then
		task.spawn(onPress)
	end
end

--- Hovered (the mouse, or a gamepad selection): it pops up and sweeps quicker and brighter.
function Badge.hover(self: any, on: boolean)
	if self.hovered == on or not self.alive then
		return
	end
	self.hovered = on
	scaleTo(self, if on then R.HoverScale else 1)
	if on then
		UISound.play("BadgeHover")
		beginSweep(self, os.clock(), true)
	end
end

--- Fade the whole badge (0 = solid, 1 = gone): the nameplates fade out far away.
function Badge.setTransparency(self: any, transparency: number)
	if self.transparency == transparency then
		return
	end
	self.transparency = transparency
	self.image.ImageTransparency = transparency
	self.shine.ImageTransparency = transparency
	self.rays.ImageTransparency = 1 - (1 - R.RaysTransparency) * (1 - transparency)
	for _, sparkle in self.sparkles do
		sparkle.ImageTransparency = transparency
	end
	for _, sparkle in self.burstSparkles do
		sparkle.ImageTransparency = transparency
	end
end

--- Destroy the badge; it leaves the shared clock (destroying its root does the same).
function Badge.destroy(self: any)
	if not self.alive then
		return
	end
	self.alive = false
	leave(self)
	stopScale(self)
	for _, connection in self.connections do
		connection:Disconnect()
	end
	self.root:Destroy()
end

--- A rank's badge image id, for static uses (Unranked for an unknown tier).
function RankBadge.image(tier: string, division: number): string
	return BADGES[Ranks.badgeKey(tier, division)] or ""
end

return RankBadge
