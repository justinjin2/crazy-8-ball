--!strict
-- TutorialHand: the tutorial's pointer hand (docs/prompts/TUTORIAL_PROMPT.md step 2; our own
-- drawing, assets/ui/tutorial/hand.png: upright with the index finger up, after the designer's
-- "tap here" icon, 2026-10-03). Its fingertip is the point it shows; it is never turned upside
-- down.
--
-- - point(target, side): solid, just under a target (TutorialOverlay.Target), tapping (it pokes
--   up and squishes on a short loop, and the tap lines over the fingertip flash). With `side`
--   it lies on its side to the target's right and pokes left, so what is over and under the
--   target stays clear (the Rank claim's rewards, the designer 2026-10-09).
-- - gesture(kind, ...): see-through demonstrations on a loop:
--     "pull"  (target)        down the power bar, all the way;
--     "hold"  (keyCode)       a gamepad button glyph held while a bar fills (Hold A);
--     "swipe" (withMouse)     across the middle of the screen, left and right (a computer adds
--                             the mouse under the hand);
--     "stick" (keyCode)       a gamepad stick glyph tilting left and right;
--     "drag"  (from, to)      from one target to another, carrying a ghost cue ball;
--     "scroll"                the mouse rolling its wheel (zoom out on a computer);
--     "pinch"                 two fingertips closing in (zoom out on a phone).
-- - nudge(): the re-prompt, a quick grow and settle.
-- - hide().
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local HudParts = require(script.Parent.HudParts)

local H = Config.Tutorial.Hand
local ART = Config.Tutorial.Art

local TutorialHand = {}
TutorialHand.__index = TutorialHand

type Target = () -> (Vector2?, Vector2?)

export type Hand = typeof(setmetatable(
	{} :: {
		root: Frame,
		hand: ImageLabel,
		rays: ImageLabel, -- the tap lines, laid over the hand
		scale: UIScale,
		mouse: ImageLabel,
		glyph: ImageLabel,
		ghost: Frame,
		ghost2: Frame, -- the pinch's second fingertip
		bar: Frame,
		barFill: Frame,
		mode: string?,
		target: Target?,
		other: Target?,
		key: Enum.KeyCode?,
		withMouse: boolean,
		clock: number,
		nudgedAt: number, -- os.clock of the last re-prompt
	},
	TutorialHand
))

local function image(parent: Instance, name: string, id: string): ImageLabel
	local i = Instance.new("ImageLabel")
	i.Name = name
	i.BackgroundTransparency = 1
	i.Image = id
	i.ScaleType = Enum.ScaleType.Fit
	i.Visible = false
	i.Parent = parent
	return i
end

local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end

function TutorialHand.new(gui: ScreenGui): Hand
	local root = Instance.new("Frame")
	root.Name = "TutorialHand"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = 8
	root.Parent = gui

	local hand = image(root, "Hand", ART.Hand)
	hand.AnchorPoint = Vector2.new(H.TipX, H.TipY)
	hand.ZIndex = 9
	local scale = Instance.new("UIScale")
	scale.Parent = hand
	local rays = image(root, "Rays", ART.HandRays)
	rays.AnchorPoint = hand.AnchorPoint
	rays.ZIndex = 9
	local mouse = image(root, "Mouse", ART.Mouse)
	mouse.AnchorPoint = Vector2.new(0.5, 0.2)
	mouse.ZIndex = 8
	local glyph = image(root, "Glyph", "")
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.ZIndex = 9

	local ghost = HudParts.frame(root, "GhostBall")
	ghost.AnchorPoint = Vector2.new(0.5, 0.5)
	ghost.BackgroundTransparency = H.GhostBallTransparency
	ghost.BackgroundColor3 = Color3.new(1, 1, 1)
	ghost.Visible = false
	ghost.ZIndex = 8
	HudParts.corner(ghost, 999)
	local ghost2 = ghost:Clone()
	ghost2.Name = "GhostBall2"
	ghost2.Parent = root

	local bar = HudParts.frame(root, "HoldBar")
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.BackgroundTransparency = 0.4
	bar.BackgroundColor3 = Color3.new(0, 0, 0)
	bar.Visible = false
	HudParts.corner(bar, 6)
	local fill = HudParts.frame(bar, "Fill")
	fill.BackgroundTransparency = 0
	fill.BackgroundColor3 = HudParts.color(Config.UI.Kit.Colors.Green)
	HudParts.corner(fill, 6)

	local self = setmetatable({
		root = root,
		hand = hand,
		rays = rays,
		scale = scale,
		mouse = mouse,
		glyph = glyph,
		ghost = ghost,
		ghost2 = ghost2,
		bar = bar,
		barFill = fill,
		mode = nil,
		target = nil,
		other = nil,
		key = nil,
		withMouse = false,
		clock = 0,
		nudgedAt = -math.huge,
	}, TutorialHand)
	RunService.RenderStepped:Connect(function(dt: number)
		self:update(dt)
	end)
	return self
end

local function handSize(): number
	local camera = workspace.CurrentCamera
	local short = if camera then math.min(camera.ViewportSize.X, camera.ViewportSize.Y) else 720
	return math.clamp(short * H.SizeShare, H.MinPx, H.MaxPx)
end

function TutorialHand.set(self: Hand, mode: string?, target: Target?, other: Target?)
	if mode ~= self.mode then
		self.clock = 0
	end
	self.mode = mode
	self.target = target
	self.other = other
end

--- Points at `target`, tapping (from its right side with `side`). Nil hides the hand.
function TutorialHand.point(self: Hand, target: Target?, side: boolean?)
	self:set(if target == nil then nil elseif side then "side" else "point", target)
end

--- Starts a see-through demonstration (see the header).
function TutorialHand.gesture(self: Hand, kind: string, a: any?, b: any?)
	self.key = nil
	self.withMouse = false
	if kind == "hold" or kind == "stick" then
		self.key = a
		self:set(kind, nil)
	elseif kind == "swipe" then
		self.withMouse = a == true
		self:set(kind, nil)
	else
		self:set(kind, a, b)
	end
end

function TutorialHand.hide(self: Hand)
	self:set(nil, nil)
end

--- The re-prompt: the hand grows and settles once.
function TutorialHand.nudge(self: Hand)
	self.nudgedAt = os.clock()
end

-- Every part hidden, then the frame's parts shown as needed.
local function reset(self: Hand)
	self.hand.Rotation = 0
	self.rays.Rotation = 0
	self.hand.Visible = false
	self.rays.Visible = false
	self.mouse.Visible = false
	self.glyph.Visible = false
	self.ghost.Visible = false
	self.ghost2.Visible = false
	self.bar.Visible = false
end

local function placeHand(self: Hand, at: Vector2, size: number, transparency: number)
	self.hand.Visible = true
	self.hand.Size = UDim2.fromOffset(size, size)
	self.hand.Position = UDim2.fromOffset(at.X, at.Y)
	self.hand.ImageTransparency = transparency
end

function TutorialHand.update(self: Hand, dt: number)
	self.clock += dt
	reset(self)
	local mode = self.mode
	if mode == nil then
		return
	end
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	local view = camera.ViewportSize
	local since = os.clock() - self.nudgedAt
	local grow = if since < H.NudgeSeconds then math.sin(since / H.NudgeSeconds * math.pi) else 0
	local size = handSize() * (1 + H.NudgeGrow * grow)
	local t = self.clock

	if mode == "point" or mode == "side" then
		local centre: Vector2?, rect: Vector2? = nil, nil
		if self.target then
			centre, rect = self.target()
		end
		if centre == nil or rect == nil then
			return
		end
		-- The tap: a quick poke up and squish, then a rest; the tap lines flash with it. Near the
		-- screen's bottom (the hotbar) it turns over and pokes down from above: turned about its
		-- middle, the tip lands at the mirrored point, so the hand shifts to keep it on target.
		local phase = (t % H.TapSeconds) / H.TapSeconds
		local dip = if phase < 0.3 then math.sin(phase / 0.3 * math.pi) else 0
		local flash = if phase < 0.6 then math.sin(phase / 0.6 * math.pi) else 0
		self.scale.Scale = 1 - H.TapSquish * dip
		if mode == "side" then
			-- Turned a quarter left about its middle: the tip, at (dx, dy) from the middle
			-- upright, lands at (dy, -dx), so the hand shifts to keep it inside the right end.
			local tip =
				Vector2.new(centre.X + rect.X / 2 - H.SideInsetPx - H.TapDipPx * dip, centre.Y)
			local dx, dy = (H.TipX - 0.5) * size, (H.TipY - 0.5) * size
			placeHand(self, tip + Vector2.new(dx - dy, dy + dx), size, 0)
			self.hand.Rotation = -90
		else
			local below = centre.Y + H.HoverPx + size * (1 - H.TipY) - view.Y
			local flip = below > size * H.FlipOffShare
			local at = centre
				+ Vector2.new(0, (if flip then -1 else 1) * (H.HoverPx - H.TapDipPx * dip))
			if flip then
				at -= Vector2.new((1 - 2 * H.TipX) * size, (1 - 2 * H.TipY) * size)
			end
			placeHand(self, at, size, 0)
			self.hand.Rotation = if flip then 180 else 0
		end
		self.rays.Visible = flash > 0
		self.rays.Size = self.hand.Size
		self.rays.Position = self.hand.Position
		self.rays.Rotation = self.hand.Rotation
		self.rays.ImageTransparency = 1 - flash
		return
	end

	self.scale.Scale = 1
	local fade = H.GestureTransparency
	local cycle = H.GestureSeconds
	local phase = (t % cycle) / cycle
	-- Each loop: move over the first 70%, hold, then fade out before starting again.
	local move = smooth(math.clamp(phase / 0.7, 0, 1))
	local out = if phase > 0.85 then (phase - 0.85) / 0.15 else 0
	local alpha = fade + (1 - fade) * out

	if mode == "pull" then
		local centre: Vector2?, rect: Vector2? = nil, nil
		if self.target then
			centre, rect = self.target()
		end
		if centre == nil or rect == nil then
			return
		end
		local top = centre.Y - rect.Y * 0.38
		local bottom = centre.Y + rect.Y * 0.42
		placeHand(self, Vector2.new(centre.X, top + (bottom - top) * move), size, alpha)
	elseif mode == "swipe" then
		local y = view.Y * H.SwipeHeightShare
		local x0, x1 =
			view.X * (0.5 - H.SwipeWidthShare / 2), view.X * (0.5 + H.SwipeWidthShare / 2)
		-- Left to right, then back (two moves a loop).
		local there = smooth(math.clamp(phase / 0.45, 0, 1))
		local back = smooth(math.clamp((phase - 0.5) / 0.45, 0, 1))
		local x = x0 + (x1 - x0) * (there - back)
		local at = Vector2.new(x, y)
		if self.withMouse then
			self.mouse.Visible = true
			self.mouse.Size = UDim2.fromOffset(size * H.MouseShare, size * H.MouseShare)
			self.mouse.Position = UDim2.fromOffset(at.X, at.Y)
			self.mouse.ImageTransparency = fade
		end
		placeHand(self, at, size, fade)
	elseif mode == "hold" or mode == "stick" then
		local key = self.key
		if key == nil then
			return
		end
		local at = Vector2.new(view.X / 2, view.Y * H.GlyphHeightShare)
		local g = size * H.GlyphShare
		self.glyph.Visible = true
		self.glyph.Image = UserInputService:GetImageForKeyCode(key)
		self.glyph.Size = UDim2.fromOffset(g, g)
		if mode == "stick" then
			local swing = math.sin(t * math.pi * 2 / H.StickSeconds)
			self.glyph.Rotation = H.StickDegrees * swing
			self.glyph.Position = UDim2.fromOffset(at.X + H.StickShiftPx * swing, at.Y)
		else
			self.glyph.Rotation = 0
			self.glyph.Position = UDim2.fromOffset(at.X, at.Y)
			local held = math.clamp(phase / 0.8, 0, 1)
			self.glyph.Size = UDim2.fromOffset(g * (1 - 0.12 * held), g * (1 - 0.12 * held))
			self.bar.Visible = true
			self.bar.Position = UDim2.fromOffset(at.X, at.Y + g * 0.62)
			self.bar.Size = UDim2.fromOffset(g * 1.6, H.HoldBarPx)
			self.barFill.Size = UDim2.fromScale(held, 1)
		end
	elseif mode == "scroll" then
		-- The mouse at the middle, rolling its wheel: a short push down, again and again.
		local at = Vector2.new(view.X / 2, view.Y * H.GlyphHeightShare)
		local roll = math.sin(math.clamp(phase / 0.6, 0, 1) * math.pi)
		self.mouse.Visible = true
		self.mouse.Size = UDim2.fromOffset(size * H.MouseShare * 1.4, size * H.MouseShare * 1.4)
		self.mouse.Position = UDim2.fromOffset(at.X, at.Y + H.ScrollPx * roll)
		self.mouse.ImageTransparency = alpha
		placeHand(self, at + Vector2.new(0, size * 0.1 + H.ScrollPx * roll), size, alpha)
	elseif mode == "pinch" then
		-- Two fingertips closing in at the middle of the screen (zoom out), the hand on one.
		local centre = Vector2.new(view.X / 2, view.Y * H.GlyphHeightShare)
		local apart = size * H.PinchApart * (1 - 0.7 * move)
		local ball = size * H.GhostBallShare
		for i, ghost in { self.ghost, self.ghost2 } do
			local side = if i == 1 then -1 else 1
			ghost.Visible = true
			ghost.Size = UDim2.fromOffset(ball, ball)
			ghost.Position =
				UDim2.fromOffset(centre.X + side * apart, centre.Y - side * apart * 0.4)
			ghost.BackgroundTransparency = H.GhostBallTransparency
				+ (1 - H.GhostBallTransparency) * out
		end
		placeHand(self, centre + Vector2.new(apart, apart * 0.4), size, alpha)
	elseif mode == "drag" then
		local from = if self.target then (self.target()) else nil
		local to = if self.other then (self.other()) else nil
		if from == nil or to == nil then
			return
		end
		local at = from:Lerp(to, move)
		local ball = size * H.GhostBallShare
		self.ghost.Visible = true
		self.ghost.Size = UDim2.fromOffset(ball, ball)
		self.ghost.Position = UDim2.fromOffset(at.X, at.Y)
		self.ghost.BackgroundTransparency = H.GhostBallTransparency
			+ (1 - H.GhostBallTransparency) * out
		placeHand(self, at, size, alpha)
	end
end

return TutorialHand
