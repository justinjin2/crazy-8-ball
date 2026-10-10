--!strict
-- TutorialOverlay: the tutorial's screen layer (docs/prompts/TUTORIAL_PROMPT.md step 2).
--
-- - The instruction line: big white Fredoka with the kit's ink outline at the top of the
--   screen, no strip behind it (designer, 2026-10-03), popping in with a soft ding on each new
--   line. A gamepad line's {R2}, {A} ... show Roblox's own button pictures in the line
--   (UserInputService:GetImageForKeyCode; tutorial v2 4.10). A re-prompt pops it again.
-- - Big text in the middle of the screen for the moments the designer marked ("Place it!").
-- - The light dim with a lit hole: four dark frames round a target (a button, a pocket, a
--   ball), built far past the screen's edges so no edge ever shows, and a pulsing ring round
--   the hole. The frames never take input: everything under them still works. The tutorial's
--   dim is a deliberate exception to UI_STYLE's "popups never darken" (designer, 2026-10-03).
-- - The small Skip tutorial button (top right) and its Yes / No confirm.
-- - The Next button under the line: a step's fallback when its action did not happen
--   (tutorial v2 7.1: never stuck).
--
-- A target is a function giving its centre and size in this layer's pixels (the whole window:
-- IgnoreGuiInset), or nil when it is not on screen; TutorialOverlay.guiTarget and worldTarget
-- make them.
local GuiService = game:GetService("GuiService")
local TextService = game:GetService("TextService")
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
		row: Frame, -- the line with button pictures (a gamepad line's tokens)
		rowFit: UIScale,
		lineText: string?,
		big: TextLabel,
		bigShown: string?,
		linePlace: string, -- "Top", "Low" (under a screen's own title) or "Near" (over the hole)
		dimFrames: { Frame },
		ring: Frame,
		ringCorner: UICorner,
		ringStroke: UIStroke,
		target: Target?,
		dimOn: boolean,
		ringOnly: boolean, -- the gold ring round the target with no dim
		dimAlpha: number, -- 0 clear .. 1 fully dimmed (eased)
		lastCentre: Vector2?, -- the hole's last place, kept while a lost target fades out
		lastSize: Vector2?,
		skip: TextButton,
		skipLeft: boolean, -- the Skip button top left (a full-screen menu's own panel is top right)
		confirm: Frame,
		onSkip: (() -> ())?,
		nextButton: TextButton,
		onNext: (() -> ())?,
		ding: Sound,
		clock: number,
		shakeAt: number, -- when the line's shake began (self.clock), or -inf
		avoid: (() -> { Vector3 })?, -- points in the world the line keeps off (a glowing pocket)
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

-- The top banner (Banner.luau's strip, the anchor Progression sets), while it shows.
local BANNER = TutorialOverlay.guiTarget("Banner", 0)

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
		row = nil :: any,
		rowFit = nil :: any,
		lineText = nil,
		big = nil :: any,
		bigShown = nil,
		linePlace = "Top",
		dimFrames = frames,
		ring = ring,
		ringStroke = stroke,
		ringCorner = corner,
		target = nil,
		dimOn = false,
		ringOnly = false,
		dimAlpha = 0,
		lastCentre = nil,
		lastSize = nil,
		skip = nil :: any,
		skipLeft = false,
		confirm = nil :: any,
		onSkip = nil,
		nextButton = nil :: any,
		onNext = nil,
		ding = ding,
		clock = 0,
		shakeAt = -math.huge,
		avoid = nil,
	}, TutorialOverlay)
	self:buildSkip()
	self:buildRow()
	local big = HudParts.text(gui, "Big", O.BigTextPx, "")
	big.AnchorPoint = Vector2.new(0.5, 0.5)
	big.ZIndex = 5
	big.Visible = false
	self.big = big
	local nextButton = HudParts.candy(gui, S.Next, function()
		if self.onNext then
			self.onNext()
		end
	end, "Green")
	nextButton.Name = "TutorialNext"
	nextButton.AnchorPoint = Vector2.new(0.5, 0)
	nextButton.ZIndex = 6
	nextButton.Visible = false
	self.nextButton = nextButton
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

-- The line with button pictures: a row of words and images, scaled down to fit the width.
function TutorialOverlay.buildRow(self: Overlay)
	local row = Instance.new("Frame")
	row.Name = "LineRow"
	row.BackgroundTransparency = 1
	row.AnchorPoint = Vector2.new(0.5, 0)
	row.ZIndex = 5
	row.Visible = false
	row.Parent = self.gui
	local fit = Instance.new("Frame")
	fit.Name = "Fit"
	fit.BackgroundTransparency = 1
	fit.Size = UDim2.fromScale(1, 1)
	fit.Parent = row
	local scale = Instance.new("UIScale")
	scale.Name = "FitScale"
	scale.Parent = fit
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, O.RowGapPx)
	layout.Parent = fit
	self.row = row
	self.rowFit = scale
end

-- The KeyCode each line token names.
local TOKENS: { [string]: Enum.KeyCode } = {
	R2 = Enum.KeyCode.ButtonR2,
	L2 = Enum.KeyCode.ButtonL2,
	RB = Enum.KeyCode.ButtonR1,
	LB = Enum.KeyCode.ButtonL1,
	A = Enum.KeyCode.ButtonA,
	B = Enum.KeyCode.ButtonB,
	X = Enum.KeyCode.ButtonX,
	Y = Enum.KeyCode.ButtonY,
	LS = Enum.KeyCode.Thumbstick1,
	RS = Enum.KeyCode.Thumbstick2,
	DPad = Enum.KeyCode.DPadUp,
}

--- `text` with each {token} as a plain word (for where no picture can go).
function TutorialOverlay.plain(text: string): string
	return (
		string.gsub(text, "{(%w+)}", function(name: string): string
			local key = TOKENS[name]
			return if key then (string.gsub(key.Name, "^Button", "")) else name
		end)
	)
end

-- Fills the row with `text`'s words and pictures (only when the text changes).
local function fillRow(self: Overlay, text: string, px: number)
	local fit = self.row:FindFirstChild("Fit") :: Frame
	for _, child in fit:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local order = 0
	local function word(chunk: string)
		if chunk == "" then
			return
		end
		order += 1
		local label = HudParts.text(fit, "Word" .. order, px, chunk)
		label.TextScaled = false
		label.TextWrapped = false
		label.LayoutOrder = order
		local width = TextService:GetTextSize(chunk, px, label.Font, Vector2.new(4000, px * 2)).X
		label.Size = UDim2.fromOffset(math.ceil(width) + 4, px * 1.3)
	end
	local at = 1
	while true do
		local a, b, name = string.find(text, "{(%w+)}", at)
		if a == nil then
			word(string.sub(text, at))
			break
		end
		word((string.gsub(string.sub(text, at, a - 1), "%s+$", "")))
		local key = TOKENS[name :: string]
		local image = if key then UserInputService:GetImageForKeyCode(key) else ""
		if image ~= "" then
			order += 1
			-- On a dark disc, like the words' outline: Roblox's light pictures vanish on a
			-- white background otherwise.
			local back = Instance.new("Frame")
			back.Name = "Key" .. order
			back.BackgroundColor3 = HudParts.tone("Ink")
			back.BackgroundTransparency = O.KeyBackTransparency
			back.BorderSizePixel = 0
			back.Size = UDim2.fromOffset(px * O.KeyScale, px * O.KeyScale)
			back.LayoutOrder = order
			local round = Instance.new("UICorner")
			round.CornerRadius = UDim.new(0.5, 0)
			round.Parent = back
			local icon = Instance.new("ImageLabel")
			icon.Name = "Picture"
			icon.BackgroundTransparency = 1
			icon.Image = image
			icon.ScaleType = Enum.ScaleType.Fit
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.fromScale(0.5, 0.5)
			icon.Size = UDim2.fromScale(O.KeyPictureShare, O.KeyPictureShare)
			icon.Parent = back
			back.Parent = fit
		else
			word(TutorialOverlay.plain("{" .. (name :: string) .. "}"))
		end
		at = (b :: number) + 1
		-- The words after a picture keep their leading space out (the layout spaces them).
		local rest = string.match(text, "^%s+", at)
		if rest then
			at += #rest
		end
	end
end

--- Shows or hides the Next button (a step's fallback); `onNext` runs when it is pressed. A
--- gamepad's selection moves onto it when it first shows.
function TutorialOverlay.setNext(self: Overlay, visible: boolean, onNext: (() -> ())?)
	local was = self.nextButton.Visible
	self.nextButton.Visible = visible
	self.onNext = if visible then onNext else nil
	if visible and not was then
		UIAnim.popIn(self.nextButton)
		if UserInputService.GamepadEnabled and GuiService.SelectedObject == nil then
			GuiService.SelectedObject = self.nextButton
		end
	elseif not visible and GuiService.SelectedObject == self.nextButton then
		GuiService.SelectedObject = nil
	end
end

--- Shows `text` as the instruction line (a new line pops in with a ding); nil hides it.
--- `place`: "Top" (the default, under Roblox's bar), "Low" (under a screen's own title) or
--- "Near" (just over the lit hole, for a full-screen menu whose top is busy). A line with
--- {tokens} shows them as Roblox's button pictures.
function TutorialOverlay.say(self: Overlay, text: string?, place: string?)
	self.linePlace = place or "Top"
	if text == self.lineText then
		return
	end
	self.lineText = text
	self.line.Visible = false
	self.row.Visible = false
	if text == nil or text == "" then
		return
	end
	if string.find(text, "{%w+}") then
		local px = if phone() then O.LinePhoneTextPx else O.LineTextPx
		fillRow(self, text, px)
		UIAnim.popIn(self.row)
	else
		self.line.Text = text
		UIAnim.popIn(self.line)
	end
	self.ding:Play()
end

--- The re-prompt: the line pops again (no ding).
function TutorialOverlay.nudge(self: Overlay)
	if self.row.Visible then
		self.row.Visible = false
		UIAnim.popIn(self.row)
	elseif self.line.Visible then
		self.line.Visible = false
		UIAnim.popIn(self.line)
	end
	if self.big.Visible then
		self.big.Visible = false
		UIAnim.popIn(self.big)
	end
end

--- The line shakes side to side (the break's release was too soft).
function TutorialOverlay.shake(self: Overlay)
	self.shakeAt = self.clock
end

--- Big text in the middle of the screen (nil hides it).
function TutorialOverlay.bigText(self: Overlay, text: string?)
	if text == self.bigShown then
		return
	end
	self.bigShown = text
	if text == nil or text == "" then
		self.big.Visible = false
		return
	end
	self.big.Text = text
	self.big.Visible = false
	UIAnim.popIn(self.big)
end

--- Dims the screen round `target` (nil: no dim). The hole follows the target every frame.
--- `on` false keeps the screen clear; `ringOnly` then still rings the target in gold.
function TutorialOverlay.dim(self: Overlay, target: Target?, on: boolean?, ringOnly: boolean?)
	self.target = target
	self.dimOn = if on == nil then target ~= nil else on
	self.ringOnly = ringOnly == true and target ~= nil
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
	-- Whole pixels, so no hairline of light shows where the four frames meet.
	local x0, y0 = math.floor(centre.X - size.X / 2), math.floor(centre.Y - size.Y / 2)
	local x1, y1 = math.ceil(centre.X + size.X / 2), math.ceil(centre.Y + size.Y / 2)
	top.Position = UDim2.fromOffset(-far, -far)
	top.Size = UDim2.fromOffset(view.X + far * 2, y0 + far)
	bottom.Position = UDim2.fromOffset(-far, y1)
	bottom.Size = UDim2.fromOffset(view.X + far * 2, view.Y - y1 + far)
	left.Position = UDim2.fromOffset(-far, y0)
	left.Size = UDim2.fromOffset(x0 + far, y1 - y0)
	right.Position = UDim2.fromOffset(x1, y0)
	right.Size = UDim2.fromOffset(view.X - x1 + far, y1 - y0)
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
	if self.linePlace == "Top" then
		-- A banner at the top (a find, a Money Party) keeps its place: the line goes under it.
		local at, size = BANNER()
		if at and size then
			gap = math.max(gap, at.Y + size.Y / 2 + O.LineTopGapPx - inset.Y)
		end
	end
	self.line.Position = UDim2.fromOffset(view.X / 2, inset.Y + gap)
	self.line.Size = UDim2.fromOffset(width, height)
	self.row.Size = UDim2.fromOffset(width, height)
	if self.row.Visible then
		local fit = self.row:FindFirstChild("Fit")
		local layout = if fit then fit:FindFirstChildOfClass("UIListLayout") else nil
		local content = if layout
			then layout.AbsoluteContentSize.X / math.max(self.rowFit.Scale, 0.01)
			else 0
		self.rowFit.Scale = if content > width then width / content else 1
	end
	-- The big text: in the middle, breathing.
	local bigPx = if small then O.BigPhoneTextPx else O.BigTextPx
	self.big.Position = UDim2.fromOffset(view.X / 2, view.Y * O.BigYScale)
	self.big.Size = UDim2.fromOffset(view.X * 0.9, bigPx * 1.3)
	-- The Skip button, top right under the bar (top left while skipLeft).
	local skipH = if small then O.SkipPhoneHeightPx else O.SkipHeightPx
	self.skip.AnchorPoint = Vector2.new(if self.skipLeft then 0 else 1, 0)
	self.skip.Position = UDim2.fromOffset(
		if self.skipLeft then O.SkipEdgePx else view.X - O.SkipEdgePx,
		inset.Y + O.SkipEdgePx
	)
	self.skip.Size = UDim2.fromOffset(skipH * O.SkipWidthRatio, skipH)
	-- The Next button, centred under the line.
	local nextH = if small then O.NextPhoneHeightPx else O.NextHeightPx
	self.nextButton.Position = UDim2.fromOffset(view.X / 2, inset.Y + gap + height + O.NextGapPx)
	self.nextButton.Size = UDim2.fromOffset(nextH * O.NextWidthRatio, nextH)
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
	-- Points to keep clear (a glowing pocket at the far end, the combination's balls: they sit
	-- right where the line is): the line moves just below the lowest one it would cover.
	local spots: { Vector3 } = {}
	if self.avoid then
		spots = self.avoid()
	end
	local ys = {}
	for _, spot in spots do
		local v, onScreen = camera:WorldToViewportPoint(spot)
		if onScreen then
			table.insert(ys, v.Y)
		end
	end
	local top = self.line.Position.Y.Offset
	for _ = 1, #ys do
		local moved = false
		for _, y in ys do
			if y > top - O.LineAvoidPx and y < top + height + O.LineAvoidPx then
				top = y + O.LineAvoidPx
				moved = true
			end
		end
		if not moved then
			break
		end
	end
	self.line.Position = UDim2.fromOffset(view.X / 2, top)
	-- The shake: a quick side-to-side that dies away.
	local shook = self.clock - self.shakeAt
	if shook < O.ShakeSeconds then
		local fade = 1 - shook / O.ShakeSeconds
		local dx = math.sin(shook * O.ShakeHz * 2 * math.pi) * O.ShakePx * fade
		self.line.Position += UDim2.fromOffset(dx, 0)
	end
	self.row.Position = self.line.Position
	self.ringStroke.Transparency = if self.ringOnly and centre then 0 else 1 - self.dimAlpha
end

--- Clears the line, the big text, the dim, the hole and the Next button.
function TutorialOverlay.clear(self: Overlay)
	self:say(nil)
	self:bigText(nil)
	self:dim(nil)
	self:setNext(false)
end

return TutorialOverlay
