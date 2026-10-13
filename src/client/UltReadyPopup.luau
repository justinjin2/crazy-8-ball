--!strict
-- UltReadyPopup: the big "ABILITY IS READY!" in the middle of the screen the first time a full
-- ability bar's press is offered (designer, 2026-10-12: "a big popup in the middle of the screen
-- saying 'ABILITY IS READY, PRESS (whatever device their on) TO USE!' briefly before vanishing
-- ... expands wiggles then shrinks"). Two lines: the title in gold, then how to use it on this
-- device: PRESS [G] TO USE! with the keycap, the controller's button on an ink disc, or TAP THE
-- ABILITY BAR TO USE! on touch. It never takes a press. UltHud decides when (once per fill);
-- the motion is StageMath.expandWiggle, sizes in Config.UI.Ults.ReadyPopup.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local StageMath = require(Shared:WaitForChild("StageMath"))
local HudParts = require(script.Parent.HudParts)
local UIAnim = require(script.Parent.UIAnim)

local U = Config.UI.Ults
local P = U.ReadyPopup
local Copy = Strings.Ults.Hud.ReadyPopup
local FONT: Enum.Font = (Enum.Font :: any)[Config.UI.Kit.Font]
local tone = HudParts.tone

local UltReadyPopup = {}
UltReadyPopup.__index = UltReadyPopup

local function words(parent: Instance, name: string, tint: Color3?, z: number): TextLabel
	local label = HudParts.text(parent, name, P.LinePx[2], "", tint)
	label.TextWrapped = false
	label.ZIndex = z
	return label
end

--- Builds the popup, hidden, on `screen` at `zIndex`.
function UltReadyPopup.new(screen: Instance, zIndex: number): any
	local self: any = setmetatable({}, UltReadyPopup)
	self.screen = screen
	self.token = 0
	self.fit = 1
	self.connection = nil :: RBXScriptConnection?

	local root = HudParts.frame(screen, "UltReadyPopup")
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, P.CentreShare)
	root.Active = false
	root.Visible = false
	root.ZIndex = zIndex
	local scale = Instance.new("UIScale")
	scale.Parent = root
	self.root, self.scale = root, scale

	local title = words(root, "Title", tone("Gold"), zIndex + 1)
	title.Text = Copy.Title
	title.AnchorPoint = Vector2.new(0.5, 0)
	self.title = title
	self.before = words(root, "Before", nil, zIndex + 1)
	self.after = words(root, "After", nil, zIndex + 1)

	-- The keyboard key: a white keycap with the ink edge (as the bar's prompt).
	local keycap = HudParts.frame(root, "Keycap")
	keycap.BackgroundTransparency = 0
	keycap.BackgroundColor3 = Color3.new(1, 1, 1)
	keycap.AnchorPoint = Vector2.new(0, 0.5)
	keycap.ZIndex = zIndex + 1
	HudParts.corner(keycap, U.KeycapCornerPx)
	local edge = Instance.new("UIStroke")
	edge.Color = tone("Ink")
	edge.Thickness = 3
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = keycap
	local letter = Instance.new("TextLabel")
	letter.Name = "Key"
	letter.BackgroundTransparency = 1
	letter.Font = FONT
	letter.TextColor3 = tone("Ink")
	letter.Text = U.KeyboardKey
	letter.AutoLocalize = false -- the key's name as printed on the keyboard
	letter.TextScaled = true
	letter.Size = UDim2.fromScale(1, 1)
	letter.ZIndex = zIndex + 2
	letter.Parent = keycap
	self.keycap = keycap

	-- The controller's button on an ink disc (Roblox's PlayStation pictures are white).
	local glyph = HudParts.frame(root, "Glyph")
	glyph.BackgroundTransparency = 0
	glyph.BackgroundColor3 = tone("Ink")
	glyph.AnchorPoint = Vector2.new(0, 0.5)
	glyph.ZIndex = zIndex + 1
	HudParts.corner(glyph, 999)
	local image = Instance.new("ImageLabel")
	image.Name = "Image"
	image.BackgroundTransparency = 1
	image.ScaleType = Enum.ScaleType.Fit
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(0.5, 0.5)
	image.Size = UDim2.fromScale(Config.UI.Kit.PadBack.GlyphShare, Config.UI.Kit.PadBack.GlyphShare)
	image.ZIndex = zIndex + 2
	image.Parent = glyph
	self.glyph, self.glyphImage = glyph, image
	return self
end

local function width(text: string, px: number): number
	if text == "" then
		return 0
	end
	return TextService:GetTextSize(text, px, FONT, Vector2.new(4000, 1000)).X
end

-- Lays the two lines out for this screen and `mode` ("key", "pad" or "tap").
function UltReadyPopup.layout(self: any, mode: string, image: string?)
	local view: Vector2 = self.screen.AbsoluteSize
	local i = if view.Y < Config.Multiplayer.Style.ShortHeight then 1 else 2
	local titlePx, linePx, gap = P.TitlePx[i], P.LinePx[i], P.GapPx[i]
	local copy = if mode == "tap" then Copy.Tap else Copy.PressKey
	local at = string.find(copy, "%s", 1, true)
	local before = if at then string.sub(copy, 1, at - 1) else copy
	local after = if at then string.sub(copy, at + 2) else ""
	local showKey = at ~= nil and mode ~= "tap"
	local keyPx = math.floor(linePx * P.KeyShare)
	-- The words' outline reaches past their measured width.
	local pad = math.ceil(linePx * Config.UI.Kit.TextOutlineRatio) * 2 + 2
	local beforeW = width(before, linePx) + pad
	local afterW = if after == "" then 0 else width(after, linePx) + pad
	local lineW = beforeW + (if showKey then keyPx else 0) + afterW
	local titleW = width(Copy.Title, titlePx) + pad
	local titleH = math.ceil(titlePx * 1.2)
	local lineH = math.max(math.ceil(linePx * 1.2), keyPx)
	local w = math.max(titleW, lineW)
	self.root.Size = UDim2.fromOffset(w, titleH + gap + lineH)
	self.fit = math.min(1, view.X * P.MaxWidthShare / math.max(w, 1))

	HudParts.setTextSize(self.title, titlePx)
	self.title.Position = UDim2.fromScale(0.5, 0)
	self.title.Size = UDim2.fromOffset(titleW, titleH)
	local y = titleH + gap + lineH / 2
	local x = (w - lineW) / 2
	local function place(label: TextLabel, text: string, labelW: number)
		label.Text = text
		label.Visible = text ~= ""
		HudParts.setTextSize(label, linePx)
		label.AnchorPoint = Vector2.new(0, 0.5)
		label.Position = UDim2.fromOffset(x, y)
		label.Size = UDim2.fromOffset(labelW, math.ceil(linePx * 1.2))
		x += labelW
	end
	place(self.before, before, beforeW)
	self.keycap.Visible = showKey and mode == "key"
	self.glyph.Visible = showKey and mode == "pad"
	self.glyphImage.Image = image or ""
	for _, box in { self.keycap, self.glyph } do
		box.Position = UDim2.fromOffset(x, y)
		box.Size = UDim2.fromOffset(keyPx, keyPx)
	end
	if showKey then
		x += keyPx
	end
	place(self.after, after, afterW)
end

--- Shows it now for `mode` ("key", "pad" with the button's picture `image`, or "tap"): it
--- expands, wiggles, holds and shrinks away on its own. `frozenAt` (Studio QA): held still at
--- that many seconds in.
function UltReadyPopup.show(self: any, mode: string, image: string?, frozenAt: number?)
	self:hide()
	self:layout(mode, image)
	self.token += 1
	local token = self.token
	local started = os.clock()
	local still = UIAnim.reduced()
	self.scale.Scale = 0
	self.root.Rotation = 0
	self.root.Visible = true
	self.connection = RunService.RenderStepped:Connect(function()
		if self.token ~= token then
			return
		end
		local t = if frozenAt then frozenAt else os.clock() - started
		local scale, degrees, done = StageMath.expandWiggle(t, P)
		self.scale.Scale = math.max(0, scale) * self.fit
		self.root.Rotation = if still then 0 else degrees
		if done then
			self:hide()
		end
	end)
end

--- Takes it away at once (a match ending, the next show).
function UltReadyPopup.hide(self: any)
	self.token += 1
	local connection = self.connection
	if connection then
		connection:Disconnect()
		self.connection = nil
	end
	self.root.Visible = false
end

--- Whether it is on screen (Studio QA).
function UltReadyPopup.showing(self: any): boolean
	return self.root.Visible
end

return UltReadyPopup
