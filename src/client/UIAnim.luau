--!strict
-- UIAnim: every UI animation, so all screens move alike (docs/UI_STYLE.md section 7). Things
-- pop in with a little overshoot and pop out quickly; only important things shine, pulse or
-- bounce (your turn, the win card, Start once it can start, a pocketed ball). Timings are in
-- Config.UI.Kit.Motion.
--
-- Two kinds of animation:
-- - Tweens for things started by an event (popIn, popOut, bounce, shine). They run on a
--   UIScale named "AnimScale" on the object, kept separate from a candy button's press scale.
-- - Pure easing curves (backOut, quadOut) for effects a screen drives every frame from the
--   server clock, so every player sees them at the same moment.
-- Looping effects (pulse, spin) return a handle; stop it when the screen closes. The hover
-- sway (sway) is switched on and off by its caller and stops by itself once off screen.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local M = Config.UI.Kit.Motion
local UIAnim = {}

export type Handle = { stop: () -> () }

--- Overshoots a little past 1, then settles: the "pop".
function UIAnim.backOut(t: number): number
	local x = math.clamp(t, 0, 1) - 1
	local c1 = 1.70158
	return 1 + (c1 + 1) * x * x * x + c1 * x * x
end

function UIAnim.quadOut(t: number): number
	local x = math.clamp(t, 0, 1)
	return 1 - (1 - x) * (1 - x)
end

--- The object's animation scale (made once, on first use).
function UIAnim.scaleOf(object: GuiObject): UIScale
	local found = object:FindFirstChild("AnimScale")
	if found and found:IsA("UIScale") then
		return found
	end
	local scale = Instance.new("UIScale")
	scale.Name = "AnimScale"
	scale.Parent = object
	return scale
end

local running: { [UIScale]: Tween } = {}

local function play(scale: UIScale, info: TweenInfo, target: number): Tween
	local old = running[scale]
	if old then
		old:Cancel()
	end
	local tween = TweenService:Create(scale, info, { Scale = target })
	running[scale] = tween
	tween.Completed:Connect(function()
		if running[scale] == tween then
			running[scale] = nil
		end
	end)
	tween:Play()
	return tween
end

--- Show an object: it grows from a little smaller, overshoots and settles.
function UIAnim.popIn(object: GuiObject)
	local scale = UIAnim.scaleOf(object)
	if not object.Visible then
		scale.Scale = M.PopFromScale
	end
	object.Visible = true
	play(scale, TweenInfo.new(M.PopSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out), 1)
end

--- Grow an object from `from` of its size (0: from nothing) to full after `delay` seconds,
--- with a small overshoot: one step of a quick one-by-one entrance (Config.UI.Kit.Motion.Stagger).
function UIAnim.expandIn(object: GuiObject, delay: number, from: number?)
	local scale = UIAnim.scaleOf(object)
	scale.Scale = from or 0
	local S = M.Stagger
	local info = TweenInfo.new(
		S.PopSeconds,
		Enum.EasingStyle.Back,
		Enum.EasingDirection.Out,
		0,
		false,
		delay
	)
	play(scale, info, 1)
end

--- Hide an object: it shrinks quickly, then is hidden. `done` runs once it is gone.
function UIAnim.popOut(object: GuiObject, done: (() -> ())?)
	if not object.Visible then
		if done then
			done()
		end
		return
	end
	local scale = UIAnim.scaleOf(object)
	local tween = play(
		scale,
		TweenInfo.new(M.OutSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		M.PopFromScale
	)
	tween.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed then
			object.Visible = false
			scale.Scale = 1
			if done then
				done()
			end
		end
	end)
end

--- A quick grow-and-settle, for a ball going down or a number changing.
function UIAnim.bounce(object: GuiObject)
	local scale = UIAnim.scaleOf(object)
	scale.Scale = M.BounceScale
	play(scale, TweenInfo.new(M.PopSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out), 1)
end

--- Breathe in and out until stopped: a button that is ready to press. `size` and `seconds`
--- make it gentler or livelier than the house pulse (Config.UI.Motion PulseScale, PulseSeconds).
function UIAnim.pulse(object: GuiObject, size: number?, seconds: number?): Handle
	local scale = UIAnim.scaleOf(object)
	scale.Scale = 1
	local tween = play(
		scale,
		TweenInfo.new(
			seconds or M.PulseSeconds,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut,
			-1,
			true
		),
		size or M.PulseScale
	)
	return {
		stop = function()
			if running[scale] == tween then
				tween:Cancel()
				running[scale] = nil
			end
			scale.Scale = 1
		end,
	}
end

--- One bright band sweeping across `object` (a card's Fill or a button's Face): for your
--- turn and the win card. The band follows the object's round corners.
function UIAnim.shine(object: GuiObject)
	local sweep = Instance.new("Frame")
	sweep.Name = "Shine"
	sweep.BackgroundColor3 = Color3.new(1, 1, 1)
	sweep.BorderSizePixel = 0
	sweep.Size = UDim2.fromScale(1, 1)
	sweep.ZIndex = object.ZIndex
	local corner = object:FindFirstChildOfClass("UICorner")
	if corner then
		corner:Clone().Parent = sweep
	end
	local band = Instance.new("UIGradient")
	band.Rotation = 20
	band.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.4, 1),
		NumberSequenceKeypoint.new(0.5, 0.35),
		NumberSequenceKeypoint.new(0.6, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	band.Offset = Vector2.new(-1, 0)
	band.Parent = sweep
	sweep.Parent = object
	local tween = TweenService:Create(
		band,
		TweenInfo.new(M.ShineSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
		{ Offset = Vector2.new(1, 0) }
	)
	tween.Completed:Connect(function()
		sweep:Destroy()
	end)
	tween:Play()
end

-- The objects swaying now (UIAnim.sway), all moved by one RenderStepped loop while any are.
type Sway = {
	on: boolean,
	weight: number, -- 0 still ... 1 the full sway, eased toward on/off
	clock: number,
	style: { [string]: number },
	watch: GuiObject,
}
local swaying: { [GuiObject]: Sway } = {}
local swayLoop: RBXScriptConnection? = nil

-- Shown: it and every GuiObject above it visible, under an enabled ScreenGui.
local function onScreen(object: GuiObject): boolean
	local node: Instance? = object
	while node do
		if node:IsA("GuiObject") then
			if not node.Visible then
				return false
			end
		elseif node:IsA("LayerCollector") then
			return node.Enabled
		end
		node = node.Parent
	end
	return false
end

local function stepSway(dt: number)
	for object, s in swaying do
		-- A screen closing under the pointer sends no MouseLeave: off screen is off.
		if s.on and not onScreen(s.watch) then
			s.on = false
		end
		local ease = dt / math.max(s.style.EaseSeconds, 0.01)
		s.weight = if s.on then math.min(1, s.weight + ease) else math.max(0, s.weight - ease)
		s.clock += dt
		if s.weight <= 0 or object.Parent == nil then
			object.Rotation = 0
			swaying[object] = nil
		else
			local style = s.style
			-- A wide thing tips less, so its ends never swing more than EdgePx.
			local half = math.max(1, object.AbsoluteSize.X / 2)
			local degrees = math.min(style.Degrees, math.deg(math.atan(style.EdgePx / half)))
			local phase = 2 * math.pi * s.clock / style.Seconds
			local wiggle = style.WiggleShare
			local rock = (math.sin(phase) + wiggle * math.sin(2 * phase)) / (1 + wiggle)
			local k = s.weight * s.weight * (3 - 2 * s.weight) -- eased in and out
			object.Rotation = degrees * k * rock
		end
	end
	if next(swaying) == nil and swayLoop then
		swayLoop:Disconnect()
		swayLoop = nil
	end
end

--- The hover sway (Config.UI.Kit.Motion.Sway, BadgeSway for `style` "Badge", CardSway for
--- "Card": a cue card's slow, small lean): while `on`,
--- `object` rocks side to side about its centre with a little wiggle, easing in from still
--- and back to still once off. It owns `object.Rotation` (keep it 0 otherwise), so sway an
--- inner frame, not one a layout turns. It stops by itself when `watch` (default `object`)
--- leaves the screen. Touch has no hover: switching on right after a tap does nothing.
function UIAnim.sway(object: GuiObject, on: boolean, style: string?, watch: GuiObject?)
	local s = swaying[object]
	if not on then
		if s then
			s.on = false
		end
		return
	end
	if UserInputService:GetLastInputType() == Enum.UserInputType.Touch then
		return
	end
	if s then
		s.on = true
		return
	end
	swaying[object] = {
		on = true,
		weight = 0,
		clock = 0,
		style = if style == "Badge"
			then M.BadgeSway
			elseif style == "Card" then M.CardSway
			else M.Sway,
		watch = watch or object,
	}
	if not swayLoop then
		swayLoop = RunService.RenderStepped:Connect(stepSway)
	end
end

--- Turn an object slowly until stopped: the rays behind the win trophy.
function UIAnim.spin(object: GuiObject, degreesPerSecond: number?): Handle
	local speed = degreesPerSecond or M.RaysDegreesPerSecond
	local connection = RunService.RenderStepped:Connect(function(dt)
		object.Rotation = (object.Rotation + speed * dt) % 360
	end)
	return {
		stop = function()
			connection:Disconnect()
		end,
	}
end

--- Count a number from `from` to `to` over `seconds` (Config.UI.Progress.CountUpSeconds by
--- default), easing out, calling `show` with each whole value and `tick` each time it changes
--- (for a ticking sound). Returns a handle; stop() jumps straight to `to`.
function UIAnim.countUp(
	from: number,
	to: number,
	show: (number) -> (),
	seconds: number?,
	tick: ((number) -> ())?
): Handle
	local duration = seconds or Config.UI.Progress.CountUpSeconds
	local started = os.clock()
	local last = math.floor(from + 0.5)
	show(last)
	local connection: RBXScriptConnection? = nil
	local function finish()
		if connection then
			connection:Disconnect()
			connection = nil
		end
		show(to)
	end
	if duration <= 0 or from == to then
		finish()
		return { stop = function() end }
	end
	connection = RunService.RenderStepped:Connect(function()
		local t = (os.clock() - started) / duration
		if t >= 1 then
			finish()
			return
		end
		local value = math.floor(from + (to - from) * UIAnim.quadOut(t) + 0.5)
		if value ~= last then
			last = value
			show(value)
			if tick then
				tick(value)
			end
		end
	end)
	return {
		stop = function()
			if connection then
				finish()
			end
		end,
	}
end

--- A burst of confetti from `origin` (a point in `parent`'s pixels): little coloured pieces
--- thrown up and out, tumbling as they fall and fade (Config.UI.Progress.Confetti).
--- `colors` defaults to the kit's bright colours; `scale` grows the burst (a new tier).
function UIAnim.confetti(parent: GuiObject, origin: Vector2, colors: { Color3 }?, scale: number?)
	local C = Config.UI.Progress.Confetti
	local k = scale or 1
	local palette: { Color3 } = {}
	if colors and #colors > 0 then
		palette = colors
	else
		for _, name in { "Gold", "Green", "Blue", "Red" } do
			local c = Config.UI.Kit.Colors[name]
			table.insert(palette, Color3.fromRGB(c[1], c[2], c[3]))
		end
	end
	local random = Random.new()
	local pieces = {}
	for i = 1, math.floor(C.Count * k) do
		local piece = Instance.new("Frame")
		piece.Name = "Confetti"
		piece.BorderSizePixel = 0
		piece.AnchorPoint = Vector2.new(0.5, 0.5)
		piece.BackgroundColor3 = palette[(i - 1) % #palette + 1]
		local w = random:NextNumber(C.SizePx[1], C.SizePx[2])
		piece.Size = UDim2.fromOffset(w, w * random:NextNumber(0.4, 0.8))
		piece.Position = UDim2.fromOffset(origin.X, origin.Y)
		piece.ZIndex = 50
		piece.Parent = parent
		table.insert(pieces, {
			frame = piece,
			vx = random:NextNumber(-1, 1) * C.SpreadPx * k,
			rise = random:NextNumber(0.5, 1) * C.RisePx * k,
			spin = random:NextNumber(-720, 720),
			delay = random:NextNumber(0, 0.12),
		})
	end
	local started = os.clock()
	local connection: RBXScriptConnection? = nil
	connection = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - started
		local alive = false
		for _, p in pieces do
			local t = math.clamp((elapsed - p.delay) / C.Seconds, 0, 1)
			if t < 1 then
				alive = true
			end
			-- Up fast, then down: a throw under gravity, spread out sideways as it goes.
			local y = -p.rise * 4 * t * (1 - t) + C.FallPx * t * t
			p.frame.Position = UDim2.fromOffset(origin.X + p.vx * UIAnim.quadOut(t), origin.Y + y)
			p.frame.Rotation = p.spin * t
			p.frame.BackgroundTransparency = math.clamp((t - 0.6) / 0.4, 0, 1)
		end
		if not alive then
			if connection then
				connection:Disconnect()
			end
			for _, p in pieces do
				p.frame:Destroy()
			end
		end
	end)
end

--------------------------------------------------------------------------------------------
-- Never still (designer, 2026-10-03; UI_STYLE 13): looping life on one shared clock. Each
-- loop runs only while its object is on screen and ends by itself once the object is gone.
--------------------------------------------------------------------------------------------

local Quality = require(script.Parent.Quality)

type Loop = { object: GuiObject, step: (number, number) -> (), clock: number, alive: boolean }
local loops: { Loop } = {}
local loopConnection: RBXScriptConnection? = nil

local function stepLoops(dt: number)
	for i = #loops, 1, -1 do
		local l = loops[i]
		if not l.alive or l.object.Parent == nil then
			table.remove(loops, i)
		elseif onScreen(l.object) then
			l.clock += dt
			l.step(l.clock, dt)
		end
	end
	if #loops == 0 and loopConnection then
		loopConnection:Disconnect()
		loopConnection = nil
	end
end

--- Run `step(clock, dt)` every frame while `object` is on screen (the clock only runs then),
--- until the handle is stopped or the object is destroyed.
function UIAnim.loop(object: GuiObject, step: (number, number) -> ()): Handle
	local l: Loop = { object = object, step = step, clock = 0, alive = true }
	table.insert(loops, l)
	if not loopConnection then
		loopConnection = RunService.RenderStepped:Connect(stepLoops)
	end
	return {
		stop = function()
			l.alive = false
		end,
	}
end

--- A quick rattle every few seconds (big words; style "Text"), or the louder "Wiggle" (one win
--- from a rank-up, an icon calling for a click). Owns `object.Rotation`. "Jolt" rattles once.
function UIAnim.shake(object: GuiObject, style: string?): Handle
	local s = M.Shake[style or "Text"] or M.Shake.Text
	local once = s.Every <= 0
	local handle: Handle
	handle = UIAnim.loop(object, function(clock)
		local phase = if once then clock else clock % s.Every
		if phase < s.Seconds then
			local fade = 1 - phase / s.Seconds
			object.Rotation = s.Degrees * math.sin(phase * s.Speed) * fade
		else
			object.Rotation = 0
			if once then
				handle.stop()
			end
		end
	end)
	return {
		stop = function()
			handle.stop()
			object.Rotation = 0
		end,
	}
end

--- A soft glow bursting out from behind `object` (a press, a hover, a menu opening), in
--- `tint` (default white). It sits inside the object under its other children. `reach`
--- scales how far it spreads (a whole menu panel uses a small one).
function UIAnim.glowBurst(object: GuiObject, tint: Color3?, reach: number?)
	local G = M.Glow
	local k = reach or 1
	-- The soft glow image fades out well inside its edge, so it reaches past the object by a
	-- pad that grows (a share of the object's smaller side): a wide button gets a halo.
	local small = math.max(8, math.min(object.AbsoluteSize.X, object.AbsoluteSize.Y))
	local glow = Instance.new("ImageLabel")
	glow.Name = "GlowBurst"
	glow.BackgroundTransparency = 1
	glow.Image = Config.UI.Kit.Art.SoftGlow
	glow.ImageColor3 = tint or Color3.new(1, 1, 1)
	glow.ImageTransparency = G.Transparency
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.new(1, small * G.FromPad * k, 1, small * G.FromPad * k)
	glow.ZIndex = -2 -- under the object's own face and words
	glow.Parent = object
	local tween = TweenService:Create(
		glow,
		TweenInfo.new(G.Seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.new(1, small * G.ToPad * k, 1, small * G.ToPad * k), ImageTransparency = 1 }
	)
	tween.Completed:Connect(function()
		glow:Destroy()
	end)
	tween:Play()
end

--- Twinkling sparkles over `object` until stopped: small 4-point stars popping up at random
--- spots, turning and fading (a deal, a rare card, the Free Reward gift).
function UIAnim.sparkle(object: GuiObject, tint: Color3?): Handle
	local S = M.Sparkle
	local random = Random.new()
	local since = 0
	local alive = 0
	return UIAnim.loop(object, function(_, dt)
		since += dt
		local max = math.max(1, math.floor(S.Max * Quality.rate() + 0.5))
		if since < S.Every or alive >= max then
			return
		end
		since = 0
		alive += 1
		local star = Instance.new("ImageLabel")
		star.Name = "Sparkle"
		star.BackgroundTransparency = 1
		star.Image = Config.UI.Kit.Art.Spark
		star.ImageColor3 = tint or Color3.new(1, 1, 1)
		star.AnchorPoint = Vector2.new(0.5, 0.5)
		star.Position =
			UDim2.fromScale(random:NextNumber(0.05, 0.95), random:NextNumber(0.05, 0.95))
		local px = random:NextNumber(S.SizePx[1], S.SizePx[2])
		star.Size = UDim2.fromOffset(0, 0)
		star.Rotation = random:NextNumber(0, 90)
		star.ZIndex = 40
		star.Parent = object
		local half = S.Seconds / 2
		local grow = TweenService:Create(
			star,
			TweenInfo.new(half, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Size = UDim2.fromOffset(px, px), Rotation = star.Rotation + 45 }
		)
		grow.Completed:Connect(function()
			local fade = TweenService:Create(
				star,
				TweenInfo.new(half, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{
					Size = UDim2.fromOffset(0, 0),
					ImageTransparency = 1,
					Rotation = star.Rotation + 45,
				}
			)
			fade.Completed:Connect(function()
				star:Destroy()
				alive -= 1
			end)
			fade:Play()
		end)
		grow:Play()
	end)
end

--- White bands sliding across `fill` (a bar's fill), clipped to its round ends: the XP bar's
--- moving pattern. The bands live in a CanvasGroup laid over the fill.
function UIAnim.stripes(fill: GuiObject, cornerPx: number?): Handle
	local S = M.Stripes
	local group = Instance.new("CanvasGroup")
	group.Name = "Stripes"
	group.BackgroundTransparency = 1
	group.Size = UDim2.fromScale(1, 1)
	group.ZIndex = fill.ZIndex + 1
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, cornerPx or 999)
	corner.Parent = group
	group.Parent = fill
	local bands: { Frame } = {}
	local handle = UIAnim.loop(group, function(clock)
		local size = group.AbsoluteSize
		local need = math.ceil((size.X + size.Y * 2) / S.GapPx) + 2
		while #bands < need do
			local band = Instance.new("Frame")
			band.BorderSizePixel = 0
			band.BackgroundColor3 = Color3.new(1, 1, 1)
			band.BackgroundTransparency = S.Transparency
			band.AnchorPoint = Vector2.new(0.5, 0.5)
			band.Rotation = S.Degrees
			band.Parent = group
			table.insert(bands, band)
		end
		local shift = (clock * S.PxPerSecond) % S.GapPx
		for i, band in bands do
			band.Size = UDim2.fromOffset(S.WidthPx, size.Y * 3)
			band.Position = UDim2.new(0, (i - 2) * S.GapPx + shift - size.Y, 0.5, 0)
		end
	end)
	return {
		stop = function()
			handle.stop()
			group:Destroy()
		end,
	}
end

-- The house rainbow (Config.Ranks.ChatRainbow) as a loop, shifted by `phase` (0..1).
local RAINBOW: { { number } } = Config.Ranks.ChatRainbow :: any
local function rainbowAt(phase: number): ColorSequence
	local keys = {}
	local n = #RAINBOW
	local function at(i: number): Color3
		local c = RAINBOW[(i - 1) % n + 1]
		return Color3.fromRGB(c[1], c[2], c[3])
	end
	-- Positions 0..1 cover one whole loop; the colour at a point slides with the phase.
	for k = 0, n do
		local t = k / n
		local shifted = (t + phase) % 1
		local index = shifted * n
		local i = math.floor(index)
		local mix = index - i
		table.insert(keys, ColorSequenceKeypoint.new(t, at(i + 1):Lerp(at(i + 2), mix)))
	end
	return ColorSequence.new(keys)
end

--- Rainbow words with their colours flowing along them (deals and multipliers only; UI_STYLE
--- 13). Works on any kit text; its outline stays ink.
function UIAnim.rainbow(label: GuiObject): Handle
	local gradient = Instance.new("UIGradient")
	gradient.Name = "Rainbow"
	gradient.Color = rainbowAt(0)
	gradient.Parent = label
	local last = -1
	local handle = UIAnim.loop(label, function(clock)
		-- About 20 steps a second is smooth enough and cheap.
		local step = math.floor(clock * 20)
		if step ~= last then
			last = step
			gradient.Color = rainbowAt((clock / M.RainbowSeconds) % 1)
		end
	end)
	return {
		stop = function()
			handle.stop()
			gradient:Destroy()
		end,
	}
end

--- A big word or card slamming in: from huge down to its size with a bump, a glow burst and
--- a jolt. For NEW RANK!, YOU PULLED, THANK YOU! `opts` calms it for a popup opened often:
--- `burst = false` drops the glow burst, `shake` names a gentler Kit.Motion.Shake ("Nudge").
function UIAnim.slam(object: GuiObject, tint: Color3?, opts: { burst: boolean?, shake: string? }?)
	local scale = UIAnim.scaleOf(object)
	scale.Scale = M.Slam.FromScale
	object.Visible = true
	local tween = play(
		scale,
		TweenInfo.new(M.Slam.Seconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		1
	)
	tween.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed then
			if not (opts and opts.burst == false) then
				UIAnim.glowBurst(object, tint)
			end
			UIAnim.shake(object, opts and opts.shake or "Jolt")
		end
	end)
end

--- Rock `object` gently side to side until stopped (an icon calling for a click). It turns,
--- never moves (a moved GUI snaps to whole pixels and steps), so a layout may place it freely.
--- Owns `object.Rotation`.
function UIAnim.bob(object: GuiObject): Handle
	local B = M.Bob
	local handle = UIAnim.loop(object, function(clock)
		object.Rotation = B.Degrees * math.sin(2 * math.pi * clock / B.Seconds)
	end)
	return {
		stop = function()
			handle.stop()
			object.Rotation = 0
		end,
	}
end

-- Sun rays behind hovered icons: one record per icon, eased in and out on one clock.
type Sun = {
	holder: Frame,
	layers: { ImageLabel },
	glow: ImageLabel,
	icon: GuiObject,
	under: GuiObject?, -- a layer the rays sit on, placed by screen pixels (else the icon's parent)
	on: boolean,
	weight: number,
	clock: number,
}
local suns: { [GuiObject]: Sun } = {}
local sunLoop: RBXScriptConnection? = nil

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function stepSuns(dt: number)
	local R = M.SunRays
	for icon, s in suns do
		if not onScreen(icon) then
			s.on = false
			s.weight = 0 -- gone with its icon at once (a layer elsewhere would linger)
		end
		local ease = dt / math.max(R.EaseSeconds, 0.01)
		s.weight = if s.on then math.min(1, s.weight + ease) else math.max(0, s.weight - ease)
		if icon.Parent == nil or s.holder.Parent == nil then
			s.holder:Destroy()
			suns[icon] = nil
		elseif s.weight <= 0 then
			s.holder.Visible = false
		else
			s.clock += dt
			local k = s.weight * s.weight * (3 - 2 * s.weight)
			local holder = s.holder
			holder.Visible = true
			-- Centred on the icon (wherever a layout put it), Reach times its size.
			local size, anchor = icon.Size, icon.AnchorPoint
			local grow = R.Reach * (R.FromScale + (1 - R.FromScale) * k)
			local under = s.under
			if under then
				local px = icon.AbsoluteSize
				local centre = icon.AbsolutePosition + px / 2 - under.AbsolutePosition
				holder.Size = UDim2.fromOffset(px.X * grow, px.Y * grow)
				holder.Position = UDim2.fromOffset(centre.X, centre.Y)
			else
				holder.Size = UDim2.new(
					size.X.Scale * grow,
					size.X.Offset * grow,
					size.Y.Scale * grow,
					size.Y.Offset * grow
				)
				holder.Position = icon.Position
					+ UDim2.new(
						(0.5 - anchor.X) * size.X.Scale,
						(0.5 - anchor.X) * size.X.Offset,
						(0.5 - anchor.Y) * size.Y.Scale,
						(0.5 - anchor.Y) * size.Y.Offset
					)
			end
			local turn = s.clock * R.DegreesPerSecond
			for i, layer in s.layers do
				layer.ImageTransparency = 1 - (1 - R.Transparency) * k
				layer.Rotation = if i == 1 then turn % 360 else (15 - turn * 0.7) % 360
			end
			s.glow.ImageTransparency = 1 - (1 - R.GlowTransparency) * k
		end
	end
	if next(suns) == nil and sunLoop then
		sunLoop:Disconnect()
		sunLoop = nil
	end
end

--- Sun rays fading in behind `icon` while `on` (a hovered icon, or a gamepad resting on it),
--- turning slowly, and fading out once off. They sit in the icon's parent just under it, or on
--- `under` (a full-screen layer under a group of icons, so they cover none of the others).
--- Touch has no hover: switching on right after a tap does nothing.
function UIAnim.sunRays(icon: GuiObject, on: boolean, under: GuiObject?)
	local s = suns[icon]
	if not on then
		if s then
			s.on = false
		end
		return
	end
	if UserInputService:GetLastInputType() == Enum.UserInputType.Touch then
		return
	end
	if s then
		s.on = true
		return
	end
	local parent = under or icon.Parent
	if not parent then
		return
	end
	local R = M.SunRays
	local holder = Instance.new("Frame")
	holder.Name = "SunRays"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.ZIndex = if under then 1 else icon.ZIndex - 1
	holder.Visible = false
	holder.Parent = parent
	local function image(name: string, art: string, scale: number): ImageLabel
		local img = Instance.new("ImageLabel")
		img.Name = name
		img.BackgroundTransparency = 1
		img.Image = art
		img.ImageColor3 = rgb(R.Color)
		img.ImageTransparency = 1
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Position = UDim2.fromScale(0.5, 0.5)
		img.Size = UDim2.fromScale(scale, scale)
		img.ZIndex = holder.ZIndex
		img.Parent = holder
		return img
	end
	local layers =
		{ image("Rays", Config.UI.Kit.Art.Rays, 1), image("Rays2", Config.UI.Kit.Art.Rays, 0.8) }
	-- The bright centre over the shafts (made last, so drawn on top), still under the icon.
	local glow = image("Glow", Config.UI.Kit.Art.SoftGlow, R.GlowShare)
	suns[icon] = {
		holder = holder,
		layers = layers,
		glow = glow,
		icon = icon,
		under = under,
		on = true,
		weight = 0,
		clock = 0,
	}
	if not sunLoop then
		sunLoop = RunService.RenderStepped:Connect(stepSuns)
	end
end

--------------------------------------------------------------------------------------------
-- The lively idle library (docs/prompts/SHOP_LIVELY_PROMPT.md section 3). Slow motion never
-- moves a label by Position or Size (Roblox snaps those to whole pixels): the label stays still
-- and the picture slides or zooms inside it through fractional ImageRectOffset/ImageRectSize, or
-- it turns by Rotation (smooth); gate 1 measured these (docs/STUDIO_NOTES.md). The maths lives
-- in StageMath. Every loop runs only while on screen (UIAnim.loop), takes its numbers from its
-- caller's Config, slows with Lower effects where it says so and keeps still with Roblox's
-- Reduce Motion (GuiService.ReducedMotionEnabled).
--------------------------------------------------------------------------------------------

local GuiService = game:GetService("GuiService")
local StageMath = require(Shared:WaitForChild("StageMath"))

-- A Studio test's stand-in for Roblox's Reduce Motion (GuiQA "reduced"; scripts cannot change
-- the player's own setting).
local testReduced = false

--- Reduce Motion is on: no floating, scrolling or spinning; fades and soft glows only.
function UIAnim.reduced(): boolean
	return GuiService.ReducedMotionEnabled or testReduced
end

--- Studio tests only (GuiQA): act as if Reduce Motion were on.
function UIAnim.testReducedMotion(on: boolean)
	if RunService:IsStudio() then
		testReduced = on
	end
end

export type FlipOptions = {
	image: string?,
	loop: boolean?,
	fps: number?,
	phase: number?,
	done: (() -> ())?,
}

-- A sheet's frame size in texels (square FramePx, or FrameWidthPx and FrameHeightPx).
local function frameSize(sheet: any): (number, number)
	return sheet.FramePx or sheet.FrameWidthPx, sheet.FramePx or sheet.FrameHeightPx
end

--- Play a flipbook on `label` (one ImageLabel, stepping ImageRectOffset). `sheet` is a
--- Config.UI.Effects entry: Image (or Sheets, several pictures holding consecutive frames),
--- Columns, Rows, the frame size, Frames, Fps. `image` picks a colour's picture when the entry
--- has several (Firework.Gold). One-shot unless `loop`; a one-shot hides the label when done
--- and calls `done`. `fps` overrides the entry's rate.
function UIAnim.flipbook(label: ImageLabel, sheet: any, opts: FlipOptions?): Handle
	local o: FlipOptions = opts or ({} :: any)
	local pictures: { string } = sheet.Sheets or { o.image or sheet.Image }
	local perSheet = sheet.Columns * sheet.Rows
	local fw, fh = frameSize(sheet)
	local fps = o.fps or sheet.Fps
	label.ImageRectSize = Vector2.new(fw, fh)
	label.Visible = true
	local handle: Handle
	handle = UIAnim.loop(label, function(clock)
		local frame = StageMath.flipFrame(clock + (o.phase or 0), fps, sheet.Frames, o.loop == true)
		if frame == nil then
			label.Visible = false
			handle.stop()
			if o.done then
				o.done()
			end
			return
		end
		local picture = pictures[frame // perSheet + 1]
		if label.Image ~= picture then
			label.Image = picture
		end
		local x, y = StageMath.flipOffset(frame % perSheet, sheet.Columns, fw, fh)
		label.ImageRectOffset = Vector2.new(x, y)
	end)
	return handle
end

--- Scroll a seamless tile inside `label` (gate 1's favourite): `label.Image` is the tile
--- repeated across a square picture of `sheetPx` texels (default 2 x 2: twice `period`), shown
--- `tilePx` screen pixels per period; the picture moves `pxPerSecond` along `direction` (screen
--- pixels, e.g. (-1, -1) for up-left at 45 degrees). The window never leaves the picture, so the
--- label must be at most `sheetPx` - `period` texels across.
function UIAnim.scrollTile(
	label: ImageLabel,
	period: number,
	tilePx: number,
	pxPerSecond: number,
	direction: Vector2,
	sheetPx: number?
): Handle
	local texel = period / tilePx
	local room = (sheetPx or period * 2) - period
	local unit = direction.Unit
	local function fit()
		local size = label.AbsoluteSize
		label.ImageRectSize =
			Vector2.new(math.min(room, size.X * texel), math.min(room, size.Y * texel))
	end
	fit()
	local resized = label:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	local handle = UIAnim.loop(label, function(clock)
		local speed = if UIAnim.reduced() then 0 else pxPerSecond
		-- The picture moves along `direction`, so the window moves the other way through it.
		local ox = StageMath.scrollOffset(clock, speed * -unit.X, texel, period)
		local oy = StageMath.scrollOffset(clock, speed * -unit.Y, texel, period)
		label.ImageRectOffset = Vector2.new(ox, oy)
	end)
	return {
		stop = function()
			handle.stop()
			resized:Disconnect()
		end,
	}
end

--- Glide `label` along `path(clock) -> (dx, dy)` screen pixels from where it stands, smooth
--- however slow: whole pixels by Position, the fraction left over by moving the picture
--- inside it. The picture needs a clear border of at least a pixel's worth of texels round its
--- content (`imagePx` square picture). Used by float and drift.
function UIAnim.glide(
	label: ImageLabel,
	imagePx: number,
	path: (number) -> (number, number)
): Handle
	local rest = label.Position
	local inner = imagePx - 4 -- a window 2 texels inside each edge, so a sub-pixel shift stays inside
	label.ImageRectSize = Vector2.new(inner, inner)
	local handle = UIAnim.loop(label, function(clock)
		local dx, dy = 0, 0
		if not UIAnim.reduced() then
			dx, dy = path(clock)
		end
		local wx, fx = StageMath.floatSplit(dx)
		local wy, fy = StageMath.floatSplit(dy)
		local texel = inner / math.max(1, label.AbsoluteSize.X)
		label.Position = rest + UDim2.fromOffset(wx, wy)
		-- Showing the picture `f` px further along means moving the window back by f texels.
		label.ImageRectOffset = Vector2.new(2 - fx * texel, 2 - fy * texel)
	end)
	return {
		stop = function()
			handle.stop()
			label.Position = rest
		end,
	}
end

--- Float `label` gently: `px` (x, y) pixels on sines of `seconds`, at a random phase; the far
--- 8-balls float less and slower (the caller scales `px` and `seconds`).
function UIAnim.float(label: ImageLabel, imagePx: number, px: Vector2, seconds: number): Handle
	local phase = Random.new():NextNumber(0, math.pi * 2)
	return UIAnim.glide(label, imagePx, function(clock)
		local a = 2 * math.pi * clock / seconds + phase
		return px.X * math.sin(a), px.Y * math.sin(a * 1.3)
	end)
end

--- Breathe `label`'s picture by `amount` (0.015 = 1.5% bigger and smaller) over `seconds`,
--- zooming the window inside a clear `border` (texels) round its content (a square picture of
--- `imagePx`). The label itself stays still.
function UIAnim.breathe(
	label: ImageLabel,
	imagePx: number,
	border: number,
	amount: number,
	seconds: number
): Handle
	local phase = Random.new():NextNumber(0, math.pi * 2)
	return UIAnim.loop(label, function(clock)
		local scale = if UIAnim.reduced()
			then 1
			else 1 + amount * math.sin(2 * math.pi * clock / seconds + phase)
		local size, at = StageMath.breatheRect(imagePx, border, scale)
		label.ImageRectSize = Vector2.new(size, size)
		label.ImageRectOffset = Vector2.new(at, at)
	end)
end

--- Pulse a glow's ImageTransparency between `low` and `high` over `seconds` (kept, softly,
--- with Reduce Motion: a glow may still breathe).
function UIAnim.glowPulse(label: ImageLabel, low: number, high: number, seconds: number): Handle
	local phase = Random.new():NextNumber(0, math.pi * 2)
	return UIAnim.loop(label, function(clock)
		local wave = 0.5 + 0.5 * math.sin(2 * math.pi * clock / seconds + phase)
		label.ImageTransparency = low + (high - low) * wave
	end)
end

--- A light sweeping across a picture's shape every `every` seconds, taking `seconds`: `mask`
--- is an ImageLabel over the piece showing its white silhouette (the *_mask.png pictures); a
--- UIGradient on it lets only a slanted band through, moved across by its Offset (smooth).
--- Lower effects sweeps half as often; Reduce Motion never.
function UIAnim.maskedSweep(
	mask: ImageLabel,
	every: number,
	seconds: number,
	strength: number?
): Handle
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 20
	local clear = 1 - (strength or 0.7)
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.42, 1),
		NumberSequenceKeypoint.new(0.5, clear),
		NumberSequenceKeypoint.new(0.58, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Offset = Vector2.new(-1, 0)
	gradient.Parent = mask
	local phase = Random.new():NextNumber(0, every)
	local handle = UIAnim.loop(mask, function(clock)
		local period = every / math.max(0.25, Quality.rate())
		local local_ = (clock + phase) % period
		if UIAnim.reduced() or local_ > seconds then
			gradient.Offset = Vector2.new(-1, 0)
			return
		end
		gradient.Offset = Vector2.new(-1 + 2 * (local_ / seconds), 0)
	end)
	return {
		stop = function()
			handle.stop()
			gradient:Destroy()
		end,
	}
end

--- A scan line sweeping down `frame` every `every` seconds, taking `seconds` (a thin bright
--- bar with a soft trail; fast enough that whole-pixel steps don't show). Not with Reduce Motion.
function UIAnim.scanLine(frame: GuiObject, tint: Color3, every: number, seconds: number): Handle
	local bar = Instance.new("Frame")
	bar.Name = "ScanLine"
	bar.BorderSizePixel = 0
	bar.BackgroundColor3 = tint
	bar.BackgroundTransparency = 0.25
	bar.Size = UDim2.new(1, 0, 0, 24)
	bar.AnchorPoint = Vector2.new(0, 1)
	bar.ZIndex = frame.ZIndex + 5
	local trail = Instance.new("UIGradient")
	trail.Rotation = 90
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.9, 0.6),
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.Parent = bar
	bar.Parent = frame
	local handle = UIAnim.loop(frame, function(clock)
		local local_ = clock % every
		local on = local_ < seconds and not UIAnim.reduced()
		bar.Visible = on
		if on then
			bar.Position = UDim2.fromScale(0, local_ / seconds)
		end
	end)
	return {
		stop = function()
			handle.stop()
			bar:Destroy()
		end,
	}
end

--- A quick glitch every `every` seconds: for `seconds` the object jumps `px` sideways and its
--- `copies` (tinted twins under it, e.g. cyan and magenta) show offset either side: a colour
--- split. Not with Reduce Motion.
function UIAnim.glitch(
	object: GuiObject,
	copies: { GuiObject },
	every: number,
	seconds: number,
	px: number
): Handle
	local rest = object.Position
	for _, c in copies do
		c.Visible = false
	end
	local phase = Random.new():NextNumber(0, every)
	local handle = UIAnim.loop(object, function(clock)
		local on = (clock + phase) % every < seconds and not UIAnim.reduced()
		object.Position = if on then rest + UDim2.fromOffset(px, 0) else rest
		for i, c in copies do
			c.Visible = on
			c.Position = rest + UDim2.fromOffset(if i % 2 == 1 then -px else px * 2, 0)
		end
	end)
	return {
		stop = function()
			handle.stop()
			object.Position = rest
			for _, c in copies do
				c.Visible = false
			end
		end,
	}
end

--- Turn `object` slowly by Rotation, `degreesPerSecond` (the block's rays, the Beta ring); a
--- rock instead when `rockDegrees` is given (swinging that far either way over `seconds`).
--- Still with Reduce Motion.
function UIAnim.turn(
	object: GuiObject,
	degreesPerSecond: number,
	rockDegrees: number?,
	seconds: number?
): Handle
	local rest = object.Rotation
	local phase = Random.new():NextNumber(0, math.pi * 2)
	local handle = UIAnim.loop(object, function(clock)
		if UIAnim.reduced() then
			object.Rotation = rest
		elseif rockDegrees then
			object.Rotation = rest
				+ rockDegrees * math.sin(2 * math.pi * clock / (seconds or 2) + phase)
		else
			object.Rotation = rest + (clock * degreesPerSecond) % 360
		end
	end)
	return {
		stop = function()
			handle.stop()
			object.Rotation = rest
		end,
	}
end

--- Gold confetti drifting down `area` and tumbling: `pictures` (image ids), `count` pieces
--- (halved with Lower effects), falling `fallPxPerSecond` with a sway, turning as they go
--- (smooth: the glide technique for the slow fall, Rotation for the tumble). Each piece wraps
--- to the top when it leaves the bottom. Not with Reduce Motion (the pieces stay put).
function UIAnim.confettiDrift(
	area: GuiObject,
	pictures: { string },
	count: number,
	sizePx: number,
	imagePx: number,
	fallPxPerSecond: number
): Handle
	local random = Random.new()
	local handles: { Handle } = {}
	local pieces: { ImageLabel } = {}
	local n = math.max(1, math.floor(count * Quality.rate() + 0.5))
	for i = 1, n do
		local piece = Instance.new("ImageLabel")
		piece.Name = "Confetti" .. i
		piece.BackgroundTransparency = 1
		piece.Image = pictures[(i - 1) % #pictures + 1]
		piece.AnchorPoint = Vector2.new(0.5, 0.5)
		piece.Size = UDim2.fromOffset(sizePx, sizePx)
		local x0 = random:NextNumber(0.03, 0.97)
		piece.Position = UDim2.fromScale(x0, 0)
		piece.Rotation = random:NextNumber(0, 360)
		piece.ZIndex = area.ZIndex + 6
		piece.Parent = area
		table.insert(pieces, piece)
		local start = random:NextNumber(0, 1)
		local swayPhase = random:NextNumber(0, math.pi * 2)
		local tumble = random:NextNumber(30, 70) * (if i % 2 == 0 then 1 else -1)
		table.insert(
			handles,
			UIAnim.glide(piece, imagePx, function(clock)
				local height = area.AbsoluteSize.Y + sizePx * 2
				local y = ((start * height + clock * fallPxPerSecond) % height) - sizePx
				return 10 * math.sin(clock * 0.9 + swayPhase), y
			end)
		)
		table.insert(handles, UIAnim.turn(piece, tumble))
	end
	return {
		stop = function()
			for _, h in handles do
				h.stop()
			end
			for _, piece in pieces do
				piece:Destroy()
			end
		end,
	}
end

--- A flipbook burst that repeats: every `every` seconds (at a random phase; Lower effects half
--- as often) `label` plays `sheet` once (Config.UI.Effects: Firework with `image`, or Sparkle) at
--- `fps`, hidden between. The corner fireworks and the twinkles. Not with Reduce Motion.
function UIAnim.burstLoop(
	label: ImageLabel,
	sheet: any,
	every: number,
	opts: { image: string?, fps: number?, phase: number? }?
): Handle
	local o: { image: string?, fps: number?, phase: number? } = opts or ({} :: any)
	local fw, fh = frameSize(sheet)
	label.Image = o.image or sheet.Image
	label.ImageRectSize = Vector2.new(fw, fh)
	label.Visible = false
	local fps = o.fps or sheet.Fps
	local phase = o.phase or Random.new():NextNumber(0, every)
	-- The loop follows the label's parent: a hidden label would never run to show itself.
	local parent = label.Parent
	local watch: GuiObject = if parent and parent:IsA("GuiObject") then parent else label
	local handle = UIAnim.loop(watch, function(clock)
		local period = every / math.max(0.25, Quality.rate())
		local frame = StageMath.flipFrame((clock + phase) % period, fps, sheet.Frames, false)
		local on = frame ~= nil and not UIAnim.reduced()
		label.Visible = on
		if on then
			local x, y = StageMath.flipOffset(frame :: number, sheet.Columns, fw, fh)
			label.ImageRectOffset = Vector2.new(x, y)
		end
	end)
	return {
		stop = function()
			handle.stop()
			label.Visible = false
		end,
	}
end

return UIAnim
