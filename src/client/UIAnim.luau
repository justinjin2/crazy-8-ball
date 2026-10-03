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

--- Breathe in and out until stopped: a button that is ready to press.
function UIAnim.pulse(object: GuiObject): Handle
	local scale = UIAnim.scaleOf(object)
	scale.Scale = 1
	local tween = play(
		scale,
		TweenInfo.new(M.PulseSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		M.PulseScale
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

--- The hover sway (Config.UI.Kit.Motion.Sway, or BadgeSway for `style` "Badge"): while `on`,
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
		style = if style == "Badge" then M.BadgeSway else M.Sway,
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

-- The drifting pattern layers (HudParts' menu and popup patterns): one clock for all, so
-- every panel's balls move together.
local drifting: { [ImageLabel]: { tile: number, x: number, y: number } } = {}
local driftClock = 0
local driftConnection: RBXScriptConnection? = nil

local function stepDrift(dt: number)
	local D = M.Drift
	driftClock += dt * (if Quality.isLow() then D.LowPxPerSecond else D.PxPerSecond)
	for tiles, d in drifting do
		if tiles.Parent == nil then
			drifting[tiles] = nil
		elseif onScreen(tiles) then
			-- Whole pixels only: the layer is redrawn just when it really moves.
			local off = math.floor(driftClock % d.tile)
			if off ~= d.x then
				d.x = off
				tiles.Position = UDim2.fromOffset(-d.tile + off, -off)
			end
		end
	end
	if next(drifting) == nil and driftConnection then
		driftConnection:Disconnect()
		driftConnection = nil
	end
end

--- Drift a tiled pattern diagonally up and to the right, forever. `tiles` must be one tile
--- (`tilePx`) wider and taller than the area it covers, inside a clipping parent.
function UIAnim.drift(tiles: ImageLabel, tilePx: number)
	drifting[tiles] = { tile = tilePx, x = -1, y = -1 }
	if not driftConnection then
		driftConnection = RunService.RenderStepped:Connect(stepDrift)
	end
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
--- a jolt. For NEW RANK!, YOU PULLED, THANK YOU!
function UIAnim.slam(object: GuiObject, tint: Color3?)
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
			UIAnim.glowBurst(object, tint)
			UIAnim.shake(object, "Jolt")
		end
	end)
end

--- Bob `object` gently up and down from where it is now until stopped (an icon calling for a
--- click). Do not use on something a layout places.
function UIAnim.bob(object: GuiObject, px: number?): Handle
	local base = object.Position
	local amount = px or M.Bob.Px
	local handle = UIAnim.loop(object, function(clock)
		local y = math.sin(2 * math.pi * clock / M.Bob.Seconds) * amount
		object.Position = base + UDim2.fromOffset(0, math.floor(y + 0.5))
	end)
	return {
		stop = function()
			handle.stop()
			object.Position = base
		end,
	}
end

return UIAnim
