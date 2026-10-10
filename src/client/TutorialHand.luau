--!strict
-- TutorialHand: the tutorial's pointer hand (docs/prompts/TUTORIAL_PROMPT.md step 2; our own
-- drawing, assets/ui/tutorial/hand.png: upright with the index finger up, after the designer's
-- "tap here" icon, 2026-10-03). Its fingertip is the point it shows; it is never turned upside
-- down.
--
-- - point(target, side, small): solid, just under a target (TutorialOverlay.Target), tapping (it
--   pokes up and squishes on a short loop, and the tap lines over the fingertip flash). With
--   `side` it lies on its side to the target's right and pokes left, so what is over and under
--   the target stays clear (the Rank claim's rewards, the designer 2026-10-09). `small` draws it
--   at Hand.SmallShare of its size (the ability's PRESS G: "way too large and covering up the
--   letter", the designer 2026-10-09).
-- - gesture(kind, ...): see-through demonstrations on a loop:
--     "pull"  (target)        down the power bar, all the way;
--     "hold"  (keyCode)       a gamepad button glyph held while a bar fills (Hold A);
--     "swipe" (withMouse)     across the middle of the screen, left and right (a computer adds
--                             the mouse under the hand);
--     "stick" (keyCode)       a gamepad stick glyph tilting left and right;
--     "stickY" (keyCode)      a gamepad stick glyph pushed up and down, the up-and-down sign
--                             beside it (zoom on a controller);
--     "drag"  (from, to)      from one target to another, carrying a ghost cue ball;
--     "scroll"                the mouse with the up-and-down sign beside it (its arrows bob
--                             apart, its dashes run down; zoom on a computer);
--     "pinch"                 two fingertips closing in, an arrow by each (zoom out on a
--                             phone: fingers spreading would zoom in).
-- The up-and-down sign (the designer's reference, 2026-10-09): an arrowhead, a column of
-- dashes, an arrowhead pointing down (the arrow's own head art).
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
local HEAD = Config.Tutorial.Arrow.Head

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
		sign: Frame, -- the up-and-down sign
		signUp: ImageLabel,
		signDown: ImageLabel,
		signDashes: { Frame },
		pinchArrows: { ImageLabel },
		mode: string?,
		target: Target?,
		other: Target?,
		key: Enum.KeyCode?,
		withMouse: boolean,
		small: boolean, -- point(..., small)
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

	local sign = HudParts.frame(root, "UpDownSign")
	sign.AnchorPoint = Vector2.new(0.5, 0.5)
	sign.Visible = false
	sign.ZIndex = 9
	local function arrowHead(parent: Instance, name: string): ImageLabel
		local a = image(parent, name, HEAD)
		a.AnchorPoint = Vector2.new(0.5, 0.5)
		a.ZIndex = 10
		return a
	end
	local signUp, signDown = arrowHead(sign, "Up"), arrowHead(sign, "Down")
	signUp.Visible, signDown.Visible = true, true
	signDown.Rotation = 180
	local dashes: { Frame } = {}
	for i = 1, H.SignDashes do
		local d = HudParts.frame(sign, "Dash" .. i)
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.BackgroundTransparency = 0
		d.BackgroundColor3 = Color3.new(1, 1, 1)
		d.ZIndex = 10
		HudParts.corner(d, 999)
		local edge = Instance.new("UIStroke")
		edge.Color = Color3.new(0, 0, 0)
		edge.Thickness = H.SignStrokePx
		edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		edge.Parent = d
		table.insert(dashes, d)
	end
	local pinchArrows = { arrowHead(root, "PinchArrow1"), arrowHead(root, "PinchArrow2") }

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
		sign = sign,
		signUp = signUp,
		signDown = signDown,
		signDashes = dashes,
		pinchArrows = pinchArrows,
		mode = nil,
		target = nil,
		small = false,
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

--- Points at `target`, tapping (from its right side with `side`, smaller with `small`). Nil
--- hides the hand.
function TutorialHand.point(self: Hand, target: Target?, side: boolean?, small: boolean?)
	self:set(if target == nil then nil elseif side then "side" else "point", target)
	self.small = small == true
end

--- Starts a see-through demonstration (see the header).
function TutorialHand.gesture(self: Hand, kind: string, a: any?, b: any?)
	self.key = nil
	self.withMouse = false
	self.small = false
	if kind == "hold" or kind == "stick" or kind == "stickY" then
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
	self.sign.Visible = false
	for _, a in self.pinchArrows do
		a.Visible = false
	end
end

-- The up-and-down sign `height` tall at `at`, at `phase` (0..1) of its loop: the arrowheads
-- bob apart and back, a light runs down the dashes.
local function placeSign(self: Hand, at: Vector2, height: number, phase: number)
	local sign = self.sign
	local w = height * H.SignWidthShare
	sign.Visible = true
	sign.Position = UDim2.fromOffset(at.X, at.Y)
	sign.Size = UDim2.fromOffset(w, height)
	local bob = H.SignBobPx * math.sin(phase * math.pi * 2)
	local head = w
	self.signUp.Size = UDim2.fromOffset(head, head)
	self.signUp.Position = UDim2.fromOffset(w / 2, head / 2 - math.max(bob, 0))
	self.signDown.Size = UDim2.fromOffset(head, head)
	self.signDown.Position = UDim2.fromOffset(w / 2, height - head / 2 + math.max(bob, 0))
	local count = #self.signDashes
	local top, bottom = head * 1.15, height - head * 1.15
	-- Each dash takes SignDashFill of its step, outline included: a gap always shows between.
	local step = (bottom - top) / math.max(count - 1, 1)
	local dashH =
		math.max(2, math.min(H.SignDashShare * w, step * H.SignDashFill - 2 * H.SignStrokePx))
	for i, d in self.signDashes do
		local y = top + (bottom - top) * (if count > 1 then (i - 1) / (count - 1) else 0.5)
		d.Size = UDim2.fromOffset(w * 0.8, dashH)
		d.Position = UDim2.fromOffset(w / 2, y)
		-- The light: the dash it is on is solid white, the rest see-through.
		local lit = math.abs(((phase * count) % count) - (i - 1))
		d.BackgroundTransparency = H.SignDashDim * math.clamp(lit, 0, 1)
	end
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
	local shrink = if self.small then H.SmallShare else 1
	local size = handSize() * shrink * (1 + H.NudgeGrow * grow)
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
			local inset = (H.SideInsetPx + H.TapDipPx * dip) * shrink
			local tip = Vector2.new(centre.X + rect.X / 2 - inset, centre.Y)
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
	elseif mode == "hold" or mode == "stick" or mode == "stickY" then
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
		elseif mode == "stickY" then
			-- Pushed up and down (a tilt toward each way), the sign beside it.
			local swing = math.sin(t * math.pi * 2 / H.StickSeconds)
			self.glyph.Rotation = 0
			self.glyph.Position = UDim2.fromOffset(at.X, at.Y - H.StickShiftPx * swing)
			local phase2 = (t % H.StickSeconds) / H.StickSeconds
			placeSign(self, at + Vector2.new(g * H.SignBesideShare, 0), g * H.SignShare, phase2)
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
		-- The mouse at the middle, the up-and-down sign beside it (no hand: it hid the wheel).
		local at = Vector2.new(view.X / 2, view.Y * H.GlyphHeightShare)
		local m = size * H.MouseShare * 1.4
		self.mouse.Visible = true
		self.mouse.Size = UDim2.fromOffset(m, m)
		self.mouse.Position = UDim2.fromOffset(at.X, at.Y)
		self.mouse.ImageTransparency = 0
		local signH = m * H.SignShare
		placeSign(self, at + Vector2.new(m * H.SignBesideShare, m * 0.3), signH, phase)
	elseif mode == "pinch" then
		-- Two fingertips closing in at the middle of the screen (zoom out), an arrow by each
		-- pointing in; they meet, hold, fade, and start apart again.
		local centre = Vector2.new(view.X / 2, view.Y * H.GlyphHeightShare)
		local ball = size * H.GhostBallShare
		local apart = math.max(size * H.PinchApart * (1 - move), ball * 0.5)
		for i, ghost in { self.ghost, self.ghost2 } do
			local side = if i == 1 then -1 else 1
			local dir = Vector2.new(side, -side * 0.4).Unit -- out from the middle
			local spot = centre + dir * apart
			ghost.Visible = true
			ghost.Size = UDim2.fromOffset(ball, ball)
			ghost.Position = UDim2.fromOffset(spot.X, spot.Y)
			ghost.BackgroundTransparency = H.GhostBallTransparency
				+ (1 - H.GhostBallTransparency) * out
			-- The arrow just outside it, pointing in (the head art points up).
			local arrow = self.pinchArrows[i]
			local a = ball * H.PinchArrowShare
			local behind = spot + dir * (ball / 2 + a * 0.6)
			arrow.Visible = true
			arrow.Size = UDim2.fromOffset(a, a)
			arrow.Position = UDim2.fromOffset(behind.X, behind.Y)
			arrow.Rotation = math.deg(math.atan2(-dir.X, dir.Y))
			arrow.ImageTransparency = out
		end
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
