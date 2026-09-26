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
-- Looping effects (pulse, spin) return a handle; stop it when the screen closes.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
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

return UIAnim
