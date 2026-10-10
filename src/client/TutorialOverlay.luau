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
-- - The small Skip tutorial button (a phone's right under Roblox's menu, a computer's top
--   right; the next free spot when one of our panels covers it) and its Yes / No confirm; a
--   controller's View button asks.
-- - The Next button under the line: a step's fallback when its action did not happen
--   (tutorial v2 7.1: never stuck); a controller's R3 presses it (never the selection).
--
-- A target is a function giving its centre and size in this layer's pixels, or nil when it is
-- not on screen; TutorialOverlay.guiTarget and worldTarget make them. This layer covers the
-- whole screen (ScreenInsets None), so its (0, 0) is the screen's corner, past any notch. Every
-- ScreenGui's AbsolutePosition (and Camera:WorldToScreenPoint) shares one space whatever its
-- insets: a place in this layer is that minus the layer's own AbsolutePosition (toLayer), and
-- the pieces sit in the play area measured by two empty probe ScreenGuis (areas;
-- src/shared/Tutorial/ScreenLayout.luau places them). Designer, 2026-10-10: on a phone with a
-- notch every hole sat beside its button while this added Roblox's top bar inset instead.
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
local PadMode = require(script.Parent.PadMode)
local UIAnim = require(script.Parent.UIAnim)
local TutorialAnchors = require(script.Parent.TutorialAnchors)
local ScreenLayout = require(Shared.Tutorial.ScreenLayout)

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
		linePx: number, -- the line's text size now (a phone's or a computer's)
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
		skipSpot: number, -- which of ScreenLayout.skipSpots Skip is on (the first one free)
		skipCheckedAt: number, -- self.clock when that was last looked at
		skipPx: number, -- Skip's text size now (0 before the first layout)
		skipWidth: number?, -- its pill's width for its words at that size
		linePick: number, -- which of ScreenLayout.lineTops the line is on
		lineCheckedAt: number, -- self.clock when that was last looked at
		nextPick: number, -- which of ScreenLayout.nextSpots Next is on
		nextCheckedAt: number,
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

-- The layer and its two probes (module level: targets are made before any overlay is).
local layer: ScreenGui? = nil
local playProbe: ScreenGui? = nil -- CoreUISafeInsets: in from the notch, under the top bar
local barProbe: ScreenGui? = nil -- TopbarSafeInsets: Roblox's top bar row right of its buttons

local function origin(): Vector2
	return if layer then layer.AbsolutePosition else Vector2.zero
end

--- A point in the shared GUI space (an AbsolutePosition, Camera:WorldToScreenPoint) in this
--- layer's pixels.
function TutorialOverlay.toLayer(point: Vector2): Vector2
	return point - origin()
end

local function rectOf(gui: ScreenGui?, fallback: ScreenLayout.Rect): ScreenLayout.Rect
	if gui == nil or gui.Parent == nil or gui.AbsoluteSize.X <= 0 then
		return fallback
	end
	local at = gui.AbsolutePosition - origin()
	return ScreenLayout.rect(at.X, at.Y, gui.AbsoluteSize.X, gui.AbsoluteSize.Y)
end

--- The screen's areas in this layer's pixels: the whole screen, the play area (in from a
--- phone's notch, under Roblox's top bar) and the top bar row right of Roblox's buttons.
function TutorialOverlay.areas(): ScreenLayout.Areas
	local camera = workspace.CurrentCamera
	local size = if layer and layer.AbsoluteSize.X > 0
		then layer.AbsoluteSize
		elseif camera then camera.ViewportSize
		else Vector2.new(1280, 720)
	local inset = GuiService:GetGuiInset()
	return {
		full = ScreenLayout.rect(0, 0, size.X, size.Y),
		play = rectOf(playProbe, ScreenLayout.rect(0, inset.Y, size.X, size.Y - inset.Y)),
		topbar = rectOf(barProbe, ScreenLayout.rect(0, 0, size.X, inset.Y)),
	}
end

--- A target on a GuiObject (or the anchor of that name), padded by `pad` pixels each side. It
--- reads the object every frame, so the hole follows it as it moves, grows or animates.
function TutorialOverlay.guiTarget(object: GuiObject | string, pad: number?): Target
	return function(): (Vector2?, Vector2?)
		local gui: GuiObject? = if type(object) == "string"
			then TutorialAnchors.get(object)
			else object :: GuiObject
		if gui == nil or not gui.Visible then
			return nil, nil
		end
		local at, size, o = gui.AbsolutePosition, gui.AbsoluteSize, origin()
		local hole = ScreenLayout.hole(at.X, at.Y, size.X, size.Y, o.X, o.Y, pad or O.HolePadPx)
		return Vector2.new(hole.x + hole.w / 2, hole.y + hole.h / 2), Vector2.new(hole.w, hole.h)
	end
end

-- Whether `gui` shows: it and every frame over it Visible, its ScreenGui on.
local function shown(gui: GuiObject): boolean
	local at: Instance? = gui
	while at and not at:IsA("LayerCollector") do
		if at:IsA("GuiObject") and not at.Visible then
			return false
		end
		at = at.Parent
	end
	return at ~= nil and (not at:IsA("ScreenGui") or at.Enabled)
end

--- A target round every shown anchor of `names` together (a button and its prompt pill): one
--- hole over all of them, padded `pad` (default HolePadPx).
function TutorialOverlay.guiTargets(names: { string }, pad: number?): Target
	return function(): (Vector2?, Vector2?)
		local low: Vector2?, high: Vector2? = nil, nil
		for _, name in names do
			local gui = TutorialAnchors.get(name)
			if gui and shown(gui) and gui.AbsoluteSize.X > 0 then
				local a, b = gui.AbsolutePosition, gui.AbsolutePosition + gui.AbsoluteSize
				low = if low then (low :: Vector2):Min(a) else a
				high = if high then (high :: Vector2):Max(b) else b
			end
		end
		if low == nil or high == nil then
			return nil, nil
		end
		local size, o = high - low, origin()
		local hole = ScreenLayout.hole(low.X, low.Y, size.X, size.Y, o.X, o.Y, pad or O.HolePadPx)
		return Vector2.new(hole.x + hole.w / 2, hole.y + hole.h / 2), Vector2.new(hole.w, hole.h)
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
		local v, onScreen = camera:WorldToScreenPoint(point)
		if not onScreen then
			return nil, nil
		end
		local r = radius
		if studs then
			local edge = camera:WorldToScreenPoint(point + camera.CFrame.RightVector * studs)
			r = math.max(r, (Vector2.new(edge.X, edge.Y) - Vector2.new(v.X, v.Y)).Magnitude)
		end
		return TutorialOverlay.toLayer(Vector2.new(v.X, v.Y)), Vector2.new(r * 2, r * 2)
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
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui.Parent = playerGui
	layer = gui
	-- Two empty ScreenGuis that only measure: the play area and the top bar row.
	local function probe(name: string, insets: Enum.ScreenInsets, ignore: boolean): ScreenGui
		local p = Instance.new("ScreenGui")
		p.Name = name
		p.ScreenInsets = insets
		p.IgnoreGuiInset = ignore
		p.ResetOnSpawn = false
		p.Parent = playerGui
		return p
	end
	playProbe = probe("TutorialPlayArea", Enum.ScreenInsets.CoreUISafeInsets, false)
	barProbe = probe("TutorialTopbarArea", Enum.ScreenInsets.TopbarSafeInsets, true)

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
		linePx = O.LineTextPx,
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
		skipSpot = 1,
		skipCheckedAt = -math.huge,
		skipPx = 0,
		skipWidth = nil,
		linePick = 1,
		lineCheckedAt = -math.huge,
		nextPick = 1,
		nextCheckedAt = -math.huge,
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
	-- Never a controller stop (a selected button takes the left stick from walking and the
	-- D-pad from the menus' route): R3 presses it instead, its picture on it.
	nextButton.Selectable = false
	local nextKey = PadMode.key(Config.Input.Gamepad.Hub.Next) :: Enum.KeyCode
	HudParts.padKey(nextButton, nextKey, Config.UI.Kit.PadKey.Button)
	ContextActionService:BindActionAtPriority(
		"TutorialNext",
		function(_, state: Enum.UserInputState)
			if state == Enum.UserInputState.Begin and nextButton.Visible and self.onNext then
				self.onNext()
				return Enum.ContextActionResult.Sink
			end
			return Enum.ContextActionResult.Pass
		end,
		false,
		Enum.ContextActionPriority.High.Value + 30,
		nextKey
	)
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
	skip.ZIndex = 6
	skip.Visible = false
	skip.Selectable = false -- the controller's View button asks instead (its picture on it)
	local skipKey = PadMode.key(Config.Input.Gamepad.Hub.Skip) :: Enum.KeyCode
	HudParts.padKey(skip, skipKey, Config.UI.Kit.PadKey.Skip)
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

	-- A gamepad opens it with the View (Select) button (Config.Input.Gamepad.Hub.Skip); the
	-- confirm takes the selection, and B answers No while it is up.
	ContextActionService:BindActionAtPriority(
		"TutorialSkip",
		function(_, state: Enum.UserInputState)
			if state == Enum.UserInputState.Begin and self.skip.Visible then
				self:askSkip(not self.confirm.Visible)
				return Enum.ContextActionResult.Sink
			end
			return Enum.ContextActionResult.Pass
		end,
		false,
		Enum.ContextActionPriority.High.Value + 30,
		skipKey
	)
end

function TutorialOverlay.askSkip(self: Overlay, open: boolean)
	local was = self.confirm.Visible
	self.confirm.Visible = open
	if open then
		UIAnim.popIn(self.confirm)
		if PadMode.active() or UserInputService.GamepadEnabled then
			GuiService.SelectedObject = self.confirm:FindFirstChild("No") :: GuiObject
		end
	elseif GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self.confirm) then
		GuiService.SelectedObject = nil
	end
	if open and not was then
		ContextActionService:BindActionAtPriority("TutorialSkipNo", function(_, state)
			if state == Enum.UserInputState.Begin then
				self:askSkip(false)
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value + 30, Enum.KeyCode.ButtonB)
	elseif was and not open then
		ContextActionService:UnbindAction("TutorialSkipNo")
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
	DLeft = Enum.KeyCode.DPadLeft,
	DRight = Enum.KeyCode.DPadRight,
	DUp = Enum.KeyCode.DPadUp,
	DDown = Enum.KeyCode.DPadDown,
	View = Enum.KeyCode.ButtonSelect,
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
		local image = if key then PadMode.glyph(key) else ""
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

--- Shows or hides the Next button (a step's fallback); `onNext` runs when it is pressed (a
--- click, a tap, or the controller's R3: Config.Input.Gamepad.Hub.Next).
function TutorialOverlay.setNext(self: Overlay, visible: boolean, onNext: (() -> ())?)
	local was = self.nextButton.Visible
	self.nextButton.Visible = visible
	self.onNext = if visible then onNext else nil
	if visible and not was then
		UIAnim.popIn(self.nextButton)
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
	self.lineCheckedAt = -math.huge
	self.line.Visible = false
	self.row.Visible = false
	if text == nil or text == "" then
		return
	end
	if string.find(text, "{%w+}") then
		fillRow(self, text, if phone() then O.LinePhoneTextPx else O.LineTextPx)
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

-- Whether `point` (GUI space) is on the letters of `object` (words with a box round them:
-- only where the letters are).
local function onWords(object: GuiObject, point: Vector2): boolean
	local any: any = object
	if not (object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox")) then
		return false
	end
	if any.Text == "" or any.TextTransparency >= 0.6 then
		return false
	end
	local words: Vector2 = any.TextBounds
	local share = Vector2.new(
		if any.TextXAlignment == Enum.TextXAlignment.Left
			then 0
			elseif any.TextXAlignment == Enum.TextXAlignment.Right then 1
			else 0.5,
		if any.TextYAlignment == Enum.TextYAlignment.Top
			then 0
			elseif any.TextYAlignment == Enum.TextYAlignment.Bottom then 1
			else 0.5
	)
	local from = object.AbsolutePosition + (object.AbsoluteSize - words) * share
	return point.X >= from.X
		and point.Y >= from.Y
		and point.X <= from.X + words.X
		and point.Y <= from.Y + words.Y
end

-- Whether `object`, found under `point` (GUI space), is something of ours Skip should not sit
-- on: a solid piece of another ScreenGui (words count where their letters are, not their whole
-- box). Screen-sized backdrops and the tutorial's layers don't count.
local function solid(object: GuiObject, point: Vector2, full: ScreenLayout.Rect): boolean
	if layer and object:IsDescendantOf(layer) then
		return false
	end
	local screen = object:FindFirstAncestorWhichIsA("ScreenGui")
	if screen == nil or not screen.Enabled or screen.Name == "TutorialSoftGui" then
		return false
	end
	local size = object.AbsoluteSize
	if size.X >= full.w * 0.9 and size.Y >= full.h * 0.9 then
		return false
	end
	local any: any = object
	if object.BackgroundTransparency < 0.6 then
		return true
	end
	if (object:IsA("ImageLabel") or object:IsA("ImageButton")) and any.Image ~= "" then
		return any.ImageTransparency < 0.6
	end
	return onWords(object, point)
end

-- How much of `spot` (this layer's pixels) our panels cover: how many of its corners and middle
-- have something solid under them (0: free).
local function covered(self: Overlay, spot: ScreenLayout.Rect, full: ScreenLayout.Rect): number
	local playerGui = self.gui.Parent
	if playerGui == nil or not playerGui:IsA("PlayerGui") then
		return 0
	end
	local o = origin()
	local e = 2
	local count = 0
	for _, point in
		{
			Vector2.new(spot.x + e, spot.y + e),
			Vector2.new(spot.x + spot.w - e, spot.y + e),
			Vector2.new(spot.x + e, spot.y + spot.h - e),
			Vector2.new(spot.x + spot.w - e, spot.y + spot.h - e),
			Vector2.new(spot.x + spot.w / 2, spot.y + spot.h / 2),
		}
	do
		local at = point + o
		for _, object in (playerGui :: PlayerGui):GetGuiObjectsAtPosition(at.X, at.Y) do
			if solid(object, at, full) then
				count += 1
				break
			end
		end
	end
	return count
end

-- How many points of `rect` (this layer's pixels) sit on another screen's words: fifteen
-- points across the line's words (0: clear).
local function wordsUnder(self: Overlay, rect: ScreenLayout.Rect): number
	local playerGui = self.gui.Parent
	if playerGui == nil or not playerGui:IsA("PlayerGui") then
		return 0
	end
	local o = origin()
	local count = 0
	for _, yShare in { 0.2, 0.5, 0.8 } do
		for _, xShare in { 0.1, 0.3, 0.5, 0.7, 0.9 } do
			local at = Vector2.new(rect.x + rect.w * xShare, rect.y + rect.h * yShare) + o
			for _, object in (playerGui :: PlayerGui):GetGuiObjectsAtPosition(at.X, at.Y) do
				local screen = object:FindFirstAncestorWhichIsA("ScreenGui")
				local ours = (layer ~= nil and object:IsDescendantOf(layer))
					or screen == nil
					or not screen.Enabled
					or screen.Name == "TutorialSoftGui"
				if not ours and onWords(object, at) then
					count += 1
					break
				end
			end
		end
	end
	return count
end

-- The line's height for its words at `px` in `width`: the lines they wrap to, at most
-- LineLines (longer words shrink to fit those).
local measured: { [string]: number } = {}
local function lineHeight(self: Overlay, width: number, px: number): number
	if self.row.Visible then
		return math.ceil(px * 1.3)
	end
	local text = self.lineText or ""
	local key = ("%d|%d|%s"):format(math.floor(width), px, text)
	local h = measured[key]
	if h == nil then
		local one = TextService:GetTextSize("Ag", px, self.line.Font, Vector2.new(10000, 10000)).Y
		local all = TextService:GetTextSize(text, px, self.line.Font, Vector2.new(width, 10000)).Y
		h = math.ceil(math.min(all, one * O.LineLines) + 4)
		measured[key] = h
	end
	return h
end

function TutorialOverlay.update(self: Overlay, dt: number)
	self.clock += dt
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	local areas = TutorialOverlay.areas()
	local full = areas.full
	local view = Vector2.new(full.w, full.h)
	local small = phone()

	-- Skip: its words at their small size, the pill as wide as they need; on the first of its
	-- spots none of our panels covers, else the least covered (looked at every
	-- SkipCheckSeconds).
	local skipPx = if small then O.SkipPhoneTextPx else O.SkipTextPx
	if skipPx ~= self.skipPx then
		self.skipPx = skipPx
		HudParts.setButtonTextSize(self.skip, skipPx, math.floor(skipPx * 0.75))
		local h = if small then O.SkipPhoneHeightPx else O.SkipHeightPx
		self.skipWidth = HudParts.candyWidth(self.skip, h, skipPx) + 2
	end
	local spots = ScreenLayout.skipSpots(areas, small, self.skipWidth)
	if self.skip.Visible and self.clock - self.skipCheckedAt >= O.SkipCheckSeconds then
		self.skipCheckedAt = self.clock
		local pick, least = 1, math.huge
		for i, spot in spots do
			local count = covered(self, spot, full)
			if count < least then
				pick, least = i, count
			end
			if count == 0 then
				break
			end
		end
		self.skipSpot = pick
	end
	local skipRect = spots[math.min(self.skipSpot, #spots)]
	self.skip.Position = UDim2.fromOffset(skipRect.x, skipRect.y)
	self.skip.Size = UDim2.fromOffset(skipRect.w, skipRect.h)

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

	-- The line: centred on the play area just under Roblox's top bar (under a banner showing
	-- there; lower for "Low"; by the hole for "Near"), clear of Skip, in as many lines as its
	-- words need up to LineLines.
	local px = if small then O.LinePhoneTextPx else O.LineTextPx
	if px ~= self.linePx then
		self.linePx = px
		HudParts.setTextSize(self.line, px)
		HudParts.setTextSize(self.big, if small then O.BigPhoneTextPx else O.BigTextPx)
	end
	local top: number? = nil
	if self.linePlace == "Low" then
		top = areas.play.y + O.LineLowGapPx
	elseif self.linePlace == "Top" then
		-- A banner at the top (a find, a Money Party) keeps its place: the line goes under it.
		local at, bannerSize = BANNER()
		if at and bannerSize then
			top = at.Y + bannerSize.Y / 2 + O.LineTopGapPx
		end
	end
	local box = ScreenLayout.line(areas, if self.skip.Visible then skipRect else nil, top)
	local height = lineHeight(self, box.w, px)
	box.h = height
	-- Where it goes: by the hole for "Near" and for a line that would cover the hole (a button
	-- at the top, like the rank HUD: under it, clear of the hand), else its usual place or a
	-- step or two lower; the first spot whose words sit on none of a screen's own (looked at
	-- every SkipCheckSeconds), else the least covered.
	local hole = if centre and size
		then ScreenLayout.rect(centre.X - size.X / 2, centre.Y - size.Y / 2, size.X, size.Y)
		else nil
	-- The words' own box (centred in the line's; a line of button pictures fills it): what
	-- must keep off the hole and off other words.
	local wordsW = if self.row.Visible
		then box.w
		else math.min(box.w, math.max(self.line.TextBounds.X, box.w * 0.3))
	local words = ScreenLayout.rect(box.x + (box.w - wordsW) / 2, box.y, wordsW, height)
	local near = hole ~= nil and (self.linePlace == "Near" or ScreenLayout.overlaps(words, hole))
	local tops = ScreenLayout.lineTops(areas, words, hole, near)
	if self.clock - self.lineCheckedAt >= O.SkipCheckSeconds then
		self.lineCheckedAt = self.clock
		local pick, least = 1, math.huge
		for i, y in tops do
			local count = wordsUnder(self, ScreenLayout.rect(words.x, y, wordsW, height))
			if count < least then
				pick, least = i, count
			end
			if count == 0 then
				break
			end
		end
		self.linePick = pick
	end
	box.y = tops[math.min(self.linePick, #tops)]
	-- Points to keep clear (a glowing pocket at the far end, the combination's balls: they sit
	-- right where the line is): the line moves just below the lowest one it would cover.
	local spots3: { Vector3 } = {}
	if self.avoid then
		spots3 = self.avoid()
	end
	local ys = {}
	for _, spot in spots3 do
		local v, onScreen = camera:WorldToScreenPoint(spot)
		if onScreen then
			table.insert(ys, TutorialOverlay.toLayer(Vector2.new(v.X, v.Y)).Y)
		end
	end
	for _ = 1, #ys do
		local moved = false
		for _, y in ys do
			if y > box.y - O.LineAvoidPx and y < box.y + height + O.LineAvoidPx then
				box.y = y + O.LineAvoidPx
				moved = true
			end
		end
		if not moved then
			break
		end
	end
	local x = box.x + box.w / 2
	-- The shake: a quick side-to-side that dies away.
	local shook = self.clock - self.shakeAt
	if shook < O.ShakeSeconds then
		local fade = 1 - shook / O.ShakeSeconds
		x += math.sin(shook * O.ShakeHz * 2 * math.pi) * O.ShakePx * fade
	end
	self.line.Position = UDim2.fromOffset(x, box.y)
	self.line.Size = UDim2.fromOffset(box.w, height)
	self.row.Position = self.line.Position
	self.row.Size = UDim2.fromOffset(box.w, height)
	if self.row.Visible then
		local fit = self.row:FindFirstChild("Fit")
		local list = if fit then fit:FindFirstChildOfClass("UIListLayout") else nil
		local content = if list
			then list.AbsoluteContentSize.X / math.max(self.rowFit.Scale, 0.01)
			else 0
		self.rowFit.Scale = if content > box.w then box.w / content else 1
	end
	-- The Next button, centred under the line, or beside its words when that covers a
	-- screen's words (else the spot covering fewest).
	local nextSpots = ScreenLayout.nextSpots(areas, box, small, wordsW)
	if self.nextButton.Visible and self.clock - self.nextCheckedAt >= O.SkipCheckSeconds then
		self.nextCheckedAt = self.clock
		local pick, least = 1, math.huge
		for i, spot in nextSpots do
			local count = wordsUnder(self, spot)
			if count < least then
				pick, least = i, count
			end
			if count == 0 then
				break
			end
		end
		self.nextPick = pick
	end
	local nextBox = nextSpots[math.min(self.nextPick, #nextSpots)]
	self.nextButton.Position = UDim2.fromOffset(nextBox.x + nextBox.w / 2, nextBox.y)
	self.nextButton.Size = UDim2.fromOffset(nextBox.w, nextBox.h)
	-- The big text: in the middle of the play area's upper part, breathing.
	local big = ScreenLayout.big(areas, small)
	self.big.Position = UDim2.fromOffset(big.x + big.w / 2, big.y + big.h / 2)
	self.big.Size = UDim2.fromOffset(big.w, big.h)
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
