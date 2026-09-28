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

return UIAnim
