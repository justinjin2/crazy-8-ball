--!strict
-- TutorialOverlay: the tutorial's screen layer (docs/prompts/TUTORIAL_PROMPT.md step 2).
--
-- - The instruction line: big white Fredoka with the kit's ink outline at the top of the
--   screen, no strip behind it (designer, 2026-10-03), popping in with a soft ding on each new
--   line.
-- - The light dim with a lit hole: four dark frames round a target (a button, a pocket, a
--   ball), built far past the screen's edges so no edge ever shows, and a pulsing ring round
--   the hole. The frames never take input: everything under them still works. The tutorial's
--   dim is a deliberate exception to UI_STYLE's "popups never darken" (designer, 2026-10-03).
-- - The small Skip tutorial button (top right) and its Yes / No confirm.
--
-- A target is a function giving its centre and size in this layer's pixels (the whole window:
-- IgnoreGuiInset), or nil when it is not on screen; TutorialOverlay.guiTarget and worldTarget
-- make them.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Strings = require(Shared.Strings)
local HudParts = require(script.Parent.HudParts)
local UIAnim = require(script.Parent.UIAnim)
local TutorialAnchors = require(script.Parent.TutorialAnchors)

local O = Config.Tutorial.Overlay
local S = Strings.Tutorial

local TutorialOverlay = {}
TutorialOverlay.__index = TutorialOverlay

export type Target = () -> (Vector2?, Vector2?)

export type Overlay = typeof(setmetatable(
	{} :: {
		gui: ScreenGui,
		line: TextLabel,
		lineText: string?,
		linePlace: string, -- "Top", "Low" (under a screen's own title) or "Near" (over the hole)
		dimFrames: { Frame },
		ring: Frame,
		ringCorner: UICorner,
		ringStroke: UIStroke,
		target: Target?,
		dimOn: boolean,
		dimAlpha: number, -- 0 clear .. 1 fully dimmed (eased)
		lastCentre: Vector2?, -- the hole's last place, kept while a lost target fades out
		lastSize: Vector2?,
		skip: TextButton,
		confirm: Frame,
		onSkip: (() -> ())?,
		ding: Sound,
		clock: number,
	},
	TutorialOverlay
))

local function phone(): boolean
	local camera = workspace.CurrentCamera
	return camera ~= nil and math.min(camera.ViewportSize.X, camera.ViewportSize.Y) < O.PhoneBelowPx
end

--- A target on a GuiObject (or the anchor of that name), padded by `pad` pixels each side.
function TutorialOverlay.guiTarget(object: GuiObject | string, pad: number?): Target
	return function(): (Vector2?, Vector2?)
		local gui: GuiObject? = if type(object) == "string"
			then TutorialAnchors.get(object)
			else object :: GuiObject
		if gui == nil or not gui.Visible then
			return nil, nil
		end
		-- AbsolutePosition is measured from under Roblox's top bar for every ScreenGui (one that
		-- ignores the inset just starts above 0); the overlay's own origin is the screen's top.
		local size = gui.AbsoluteSize
		local centre = gui.AbsolutePosition + GuiService:GetGuiInset() + size / 2
		local grow = (pad or O.HolePadPx) * 2
		return centre, size + Vector2.new(grow, grow)
	end
end

--- A target round a point in the world, `radius` pixels (or the radius a world `studs` sphere
--- covers on screen, whichever is bigger).
function TutorialOverlay.worldTarget(
	at: Vector3 | () -> Vector3?,
	radius: number,
	studs: number?
): Target
	return function(): (Vector2?, Vector2?)
		local camera = workspace.CurrentCamera
		local point: Vector3? = if typeof(at) == "Vector3" then at else (at :: () -> Vector3?)()
		if camera == nil or point == nil then
			return nil, nil
		end
		local v, onScreen = camera:WorldToViewportPoint(point)
		if not onScreen then
			return nil, nil
		end
		local r = radius
		if studs then
			local edge = camera:WorldToViewportPoint(point + camera.CFrame.RightVector * studs)
			r = math.max(r, (Vector2.new(edge.X, edge.Y) - Vector2.new(v.X, v.Y)).Magnitude)
		end
		return Vector2.new(v.X, v.Y), Vector2.new(r * 2, r * 2)
	end
end

local function dimFrame(parent: Instance, name: string): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundColor3 = Color3.new(0, 0, 0)
	f.BackgroundTransparency = 1
	f.Active = false
	f.ZIndex = 1
	f.Parent = parent
	return f
end

function TutorialOverlay.new(): Overlay
	local gui = Instance.new("ScreenGui")
	gui.Name = "TutorialGui"
	gui.IgnoreGuiInset = true
	-- The whole screen, past a phone's safe area, so the dim never stops short of an edge.
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ResetOnSpawn = false
	gui.DisplayOrder = O.DisplayOrder
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local frames = {}
	for _, name in { "DimTop", "DimBottom", "DimLeft", "DimRight" } do
		table.insert(frames, dimFrame(gui, name))
	end

	local ring = Instance.new("Frame")
	ring.Name = "HoleRing"
	ring.BackgroundTransparency = 1
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Visible = false
	ring.ZIndex = 2
	ring.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, O.RingCornerPx)
	corner.Parent = ring
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = O.RingThicknessPx
	stroke.Color = HudParts.color(O.RingColor)
	stroke.Parent = ring

	local line = HudParts.text(gui, "Line", O.LineTextPx, "")
	line.AnchorPoint = Vector2.new(0.5, 0)
	line.ZIndex = 5
	line.Visible = false

	local ding = Instance.new("Sound")
	ding.Name = "TutorialDing"
	ding.SoundId = O.Ding.Id
	ding.Volume = O.Ding.Volume
	ding.Parent = SoundService

	local self = setmetatable({
		gui = gui,
		line = line,
		lineText = nil,
		linePlace = "Top",
		dimFrames = frames,
		ring = ring,
		ringStroke = stroke,
		ringCorner = corner,
		target = nil,
		dimOn = false,
		dimAlpha = 0,
		lastCentre = nil,
		lastSize = nil,
		skip = nil :: any,
		confirm = nil :: any,
		onSkip = nil,
		ding = ding,
		clock = 0,
	}, TutorialOverlay)
	self:buildSkip()
	RunService.RenderStepped:Connect(function(dt: number)
		self:update(dt)
	end)
	return self
end

-- The Skip tutorial button and its confirm card.
function TutorialOverlay.buildSkip(self: Overlay)
	local skip = HudParts.candy(self.gui, S.Skip, function()
		self:askSkip(true)
	end, "Grey")
	skip.Name = "SkipTutorial"
	skip.AnchorPoint = Vector2.new(1, 0)
	skip.ZIndex = 6
	skip.Visible = false
	self.skip = skip

	local card = HudParts.card(self.gui, "SkipConfirm")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(O.ConfirmSize[1], O.ConfirmSize[2])
	card.ZIndex = 10
	card.Visible = false
	local ask = HudParts.note(card, "Ask", O.ConfirmTextPx, S.SkipAsk)
	ask.Position = UDim2.fromScale(0.08, 0.1)
	ask.Size = UDim2.fromScale(0.84, 0.4)
	local yes = HudParts.candy(card, S.SkipYes, function()
		self:askSkip(false)
		if self.onSkip then
			self.onSkip()
		end
	end, "Red")
	yes.Name = "Yes"
	yes.Position = UDim2.fromScale(0.08, 0.58)
	yes.Size = UDim2.fromScale(0.38, 0.3)
	local no = HudParts.candy(card, S.SkipNo, function()
		self:askSkip(false)
	end, "Blue")
	no.Name = "No"
	no.Position = UDim2.fromScale(0.54, 0.58)
	no.Size = UDim2.fromScale(0.38, 0.3)
	self.confirm = card

	-- A gamepad opens it with the View (Select) button; the confirm takes the selection.
	ContextActionService:BindAction("TutorialSkip", function(_, state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin and self.skip.Visible then
			self:askSkip(not self.confirm.Visible)
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.ButtonSelect)
end

function TutorialOverlay.askSkip(self: Overlay, open: boolean)
	self.confirm.Visible = open
	if open then
		UIAnim.popIn(self.confirm)
		if UserInputService.GamepadEnabled then
			GuiService.SelectedObject = self.confirm:FindFirstChild("No") :: GuiObject
		end
	elseif GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self.confirm) then
		GuiService.SelectedObject = nil
	end
end

--- Shows or hides the Skip tutorial button; `onSkip` runs on Yes.
function TutorialOverlay.setSkip(self: Overlay, visible: boolean, onSkip: (() -> ())?)
	self.skip.Visible = visible
	self.onSkip = onSkip
	if not visible then
		self:askSkip(false)
	end
end

--- Shows `text` as the instruction line (a new line pops in with a ding); nil hides it.
--- `place`: "Top" (the default, under Roblox's bar), "Low" (under a screen's own title) or
--- "Near" (just over the lit hole, for a full-screen menu whose top is busy).
function TutorialOverlay.say(self: Overlay, text: string?, place: string?)
	self.linePlace = place or "Top"
	if text == self.lineText then
		return
	end
	self.lineText = text
	if text == nil or text == "" then
		self.line.Visible = false
		return
	end
	self.line.Text = text
	self.line.Visible = true
	UIAnim.popIn(self.line)
	self.ding:Play()
end

--- Dims the screen round `target` (nil: no dim). The hole follows the target every frame.
function TutorialOverlay.dim(self: Overlay, target: Target?, on: boolean?)
	self.target = target
	self.dimOn = if on == nil then target ~= nil else on
end

-- Lays the dim frames round the hole (centre, size) or over everything (no hole).
local function layout(self: Overlay, centre: Vector2?, size: Vector2?, view: Vector2)
	local far = O.BeyondEdgePx
	local top, bottom, left, right =
		self.dimFrames[1], self.dimFrames[2], self.dimFrames[3], self.dimFrames[4]
	if centre == nil or size == nil then
		top.Position = UDim2.fromOffset(-far, -far)
		top.Size = UDim2.fromOffset(view.X + far * 2, view.Y + far * 2)
		for _, f in { bottom, left, right } do
			f.Size = UDim2.fromOffset(0, 0)
		end
		self.ring.Visible = false
		return
	end
	local x0, y0 = centre.X - size.X / 2, centre.Y - size.Y / 2
	local x1, y1 = x0 + size.X, y0 + size.Y
	top.Position = UDim2.fromOffset(-far, -far)
	top.Size = UDim2.fromOffset(view.X + far * 2, y0 + far)
	bottom.Position = UDim2.fromOffset(-far, y1)
	bottom.Size = UDim2.fromOffset(view.X + far * 2, view.Y - y1 + far)
	left.Position = UDim2.fromOffset(-far, y0)
	left.Size = UDim2.fromOffset(x0 + far, size.Y)
	right.Position = UDim2.fromOffset(x1, y0)
	right.Size = UDim2.fromOffset(view.X - x1 + far, size.Y)
	self.ring.Visible = true
	self.ring.Position = UDim2.fromOffset(centre.X, centre.Y)
	local pulse = 1
		+ O.RingPulse * (0.5 + 0.5 * math.sin(self.clock * math.pi * 2 / O.RingPulseSeconds))
	self.ring.Size = UDim2.fromOffset(size.X * pulse, size.Y * pulse)
	self.ringCorner.CornerRadius =
		UDim.new(0, math.min(O.RingCornerPx, math.min(size.X, size.Y) / 2))
end

function TutorialOverlay.update(self: Overlay, dt: number)
	self.clock += dt
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	local view = camera.ViewportSize
	local small = phone()
	-- The line: under Roblox's top bar, centred, wide enough for long translations.
	local inset = GuiService:GetGuiInset()
	local width = math.min(view.X * O.LineWidthScale, O.LineMaxWidthPx)
	local height = if small then O.LinePhoneHeightPx else O.LineHeightPx
	local gap = if self.linePlace == "Low" then O.LineLowGapPx else O.LineTopGapPx
	self.line.Position = UDim2.fromOffset(view.X / 2, inset.Y + gap)
	self.line.Size = UDim2.fromOffset(width, height)
	-- The Skip button, top right under the bar.
	local skipH = if small then O.SkipPhoneHeightPx else O.SkipHeightPx
	self.skip.Position = UDim2.fromOffset(view.X - O.SkipEdgePx, inset.Y + O.SkipEdgePx)
	self.skip.Size = UDim2.fromOffset(skipH * O.SkipWidthRatio, skipH)
	-- The hole's target this frame; a target that has gone (its button hid) fades the dim out
	-- round where it was, rather than darkening everything.
	local centre, size = nil, nil
	if self.target then
		centre, size = self.target()
		if centre then
			self.lastCentre, self.lastSize = centre, size
		end
	end
	local lost = self.target ~= nil and centre == nil
	if lost then
		centre, size = self.lastCentre, self.lastSize
	end
	-- The dim eases in and out.
	local goal = if self.dimOn and not lost then 1 else 0
	local step = dt / O.DimFadeSeconds
	self.dimAlpha = if goal > self.dimAlpha
		then math.min(goal, self.dimAlpha + step)
		else math.max(goal, self.dimAlpha - step)
	local alpha = 1 - (1 - O.DimTransparency) * self.dimAlpha
	for _, f in self.dimFrames do
		f.BackgroundTransparency = alpha
	end
	layout(self, centre, size, view)
	if self.linePlace == "Near" and centre and size then
		-- Over the hole (under it when the hole is near the top), never under the top bar.
		local above = centre.Y - size.Y / 2 - O.LineNearGapPx
		local y = if above - height >= inset.Y + O.LineTopGapPx
			then above - height
			else centre.Y + size.Y / 2 + O.LineNearGapPx
		self.line.Position = UDim2.fromOffset(view.X / 2, y)
	end
	self.ringStroke.Transparency = 1 - self.dimAlpha
end

--- Clears the line, the dim and the hole.
function TutorialOverlay.clear(self: Overlay)
	self:say(nil)
	self:dim(nil)
end

return TutorialOverlay
