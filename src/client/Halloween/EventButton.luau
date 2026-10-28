--!strict
-- EventButton: the Halloween tile on the hub's right side (hw-core; R1.8). HubCorners builds it
-- with the other corner tiles (it hides with them in a match and under popups) and lays it out
-- through Halloween/TileLayout: the Daily Challenge's spot, or next to the offer tile while that
-- shows. It shows only while the event is Live for a player whose tutorial is over
-- (Halloween/State). A pumpkin with candy, the word HALLOWEEN, an "ENDS IN 5d 23h" pill over
-- its top, NEW until the menu was opened once, a red "!" while a quest waits to be claimed or a
-- new board has opened since the menu was last opened. A press opens the event menu.
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Clock = require(Shared.Halloween.Clock)
local Event = require(Shared.Halloween.Event)
local TileLayout = require(Shared.Halloween.TileLayout)
local HudParts = require(script.Parent.Parent.HudParts)
local Menus = require(script.Parent.Parent.Menus)
local UIAnim = require(script.Parent.Parent.UIAnim)
local UISound = require(script.Parent.Parent.UISound)
local Countdown = require(script.Parent.Countdown)
local State = require(script.Parent.State)

local T = Config.UI.Halloween.Tile
local C = Config.UI.Corners
local K = Config.UI.Kit
local W = Strings.Halloween

local EventButton = {}
EventButton.__index = EventButton

-- The menu's name in Menus (Halloween/EventMenu registers it).
EventButton.MenuName = "Halloween"

local function round(n: number): number
	return math.floor(n + 0.5)
end

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

-- The controller's selection: the kit's gold outline round the tile (as the other corners').
local function padRing(): Frame
	local ring = Instance.new("Frame")
	ring.Name = "PadRing"
	ring.BackgroundTransparency = 1
	ring.Size = UDim2.fromScale(1, 1)
	HudParts.corner(ring, C.PadRingCornerPx)
	local stroke = Instance.new("UIStroke")
	stroke.Color = HudParts.tone("Gold")
	stroke.Thickness = C.PadRingPx
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = ring
	return ring
end

local function badge(parent: Instance, name: string, tone: string, words: string): Frame
	local dot = HudParts.pill(parent, name, HudParts.tone(tone))
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.ZIndex = 6
	dot.Visible = false
	local text = HudParts.text(dot, "Words", C.WordPx + 1, words)
	text.TextWrapped = false
	text.Size = UDim2.fromScale(1, 1)
	text.ZIndex = 7
	return dot
end

--- Builds the tile under `root` (HubCorners' frame). `corners` is the HubCorners object: its
--- layout() places the tile (EventButton.layout) and its padFocused says whether the D-pad's
--- left made the corner tiles stops.
function EventButton.new(root: Frame, corners: any): any
	local self = setmetatable({}, EventButton) :: any
	self.corners = corners
	self.connections = {}
	self.shown = false
	self.openedBoard = 0 -- the newest board when the menu was last opened (this visit)

	local button = HudParts.candy(root, "", function()
		self:press()
	end, "Blue", nil)
	button.Name = "HalloweenTile"
	button.Selectable = false
	button.SelectionImageObject = padRing()
	button.Visible = false
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	local parts = HudParts.candyParts(button)
	parts.face.Visible = false
	local body = parts.body
	-- A soft orange glow behind the pumpkin, breathing.
	local glow = Instance.new("ImageLabel")
	glow.Name = "Glow"
	glow.BackgroundTransparency = 1
	glow.Image = K.Art.SoftGlow
	glow.ImageColor3 = rgb(T.GlowTint)
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.45)
	glow.Size = UDim2.fromScale(1.9, 1.9)
	glow.ZIndex = 1
	glow.Parent = body
	UIAnim.glowPulse(glow, 0.35, 0.75, 1.6)
	local icon = Instance.new("ImageLabel")
	icon.Name = "Art"
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = if T.Icon ~= "" then T.Icon else Config.Halloween.CandyIcon
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.45)
	icon.Size = UDim2.fromScale(1.05, 1.05)
	icon.ZIndex = 3
	icon.Parent = body
	UIAnim.shake(icon, "Wiggle")
	local word = HudParts.text(body, "Word", T.WordPx, W.Name)
	word.TextWrapped = false
	word.AnchorPoint = Vector2.new(0.5, 0.5)
	word.Position = UDim2.fromScale(0.5, 0.92)
	word.ZIndex = 4
	UIAnim.rainbow(word)
	HudParts.onLit(button, function(lit: boolean)
		UIAnim.sunRays(icon, lit)
	end)
	-- "ENDS IN 5d 23h" on a purple pill over the top edge.
	local pill = HudParts.pill(body, "Ends", HudParts.tone("Purple"))
	pill.AnchorPoint = Vector2.new(0.5, 0.5)
	pill.Position = UDim2.fromScale(0.5, 0)
	pill.ZIndex = 5
	local ends = HudParts.text(pill, "Time", T.PillTextPx, "")
	ends.AutoLocalize = false
	ends.TextWrapped = false
	ends.Size = UDim2.fromScale(1, 1)
	ends.ZIndex = 6
	self.button, self.icon, self.word, self.pill, self.ends = button, icon, word, pill, ends
	-- NEW on the left edge and the red "!" on the right, under the pill.
	self.fresh = badge(body, "New", "Green", W.New)
	self.fresh.Position = UDim2.fromScale(0.02, 0.36)
	self.alert = badge(body, "Alert", "Red", "!")
	self.alert.Position = UDim2.fromScale(0.98, 0.36)

	table.insert(
		self.connections,
		State.Changed:Connect(function()
			self:refresh()
		end)
	)
	-- Off the controller's stops once the corners let go of the D-pad (HubCorners.blurPad).
	table.insert(
		self.connections,
		GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
			if not corners.padFocused and button.Selectable then
				button.Selectable = false
			end
		end)
	)
	-- The pill's time and the event's start and end: once a second.
	task.spawn(function()
		while button.Parent ~= nil do
			self:refresh()
			task.wait(1)
		end
	end)
	return self
end

-- Whether the tile should show now: the event Live for this player, after 19:00's start
-- message (Halloween/Countdown).
function EventButton.wanted(_self: any): boolean
	return State.phase() == "Live" and not Countdown.holding()
end

-- Whether a quest waits to be claimed, or a board opened since the menu was last opened.
local function alerting(self: any, view: any?): boolean
	if type(view) ~= "table" or type(view.boards) ~= "table" then
		return false
	end
	if view.on and view.on.quests then
		for _, board in view.boards do
			for _, q in board.quests or {} do
				if not q.claimed and q.have >= q.need then
					return true
				end
			end
		end
		if view.seen and (view.open or 0) > self.openedBoard and self.openedBoard > 0 then
			return true
		end
	end
	return false
end

function EventButton.refresh(self: any)
	local show = self:wanted()
	if show ~= self.shown then
		self.shown = show
		if show then
			UIAnim.popIn(self.button)
		else
			self.button.Visible = false
		end
		self.corners:layout()
	end
	if not show then
		return
	end
	local view = State.view()
	self.ends.Text = W.EndsIn:format(Event.short(Event.endsIn(Clock.now())))
	self:sizePill()
	local fresh = type(view) == "table" and view.seen ~= true
	if self.fresh.Visible ~= fresh then
		self.fresh.Visible = fresh
		if fresh then
			UIAnim.bounce(self.fresh)
		end
	end
	local alert = alerting(self, view)
	if self.alert.Visible ~= alert then
		self.alert.Visible = alert
		if alert then
			UIAnim.bounce(self.alert)
		end
	end
end

function EventButton.sizePill(self: any)
	local px = self.pillTextPx or T.PillTextPx
	local width = TextService:GetTextSize(
		self.ends.Text,
		px,
		(Enum.Font :: any)[K.Font],
		Vector2.new(400, 100)
	).X
	local h = self.pillPx or T.PillPx
	self.pill.Size = UDim2.fromOffset(math.max(h * 2, math.ceil(width) + 14), h)
end

--- Places the tile (HubCorners.layout): `centreX` is the right column's middle in the screen's
--- pixels, `offer` the offer tile's whole box while it shows.
function EventButton.layout(
	self: any,
	size: Vector2,
	short: boolean,
	centreX: number,
	offer: TileLayout.Box?
)
	local px = if short then T.ShortPx else T.Px
	local wordPx = if short then T.ShortWordPx else T.WordPx
	local pillPx = if short then T.ShortPillPx else T.PillPx
	local pillTextPx = if short then T.ShortPillTextPx else T.PillTextPx
	self.pillPx, self.pillTextPx = pillPx, pillTextPx
	local wordWidth = TextService:GetTextSize(
		W.Name,
		wordPx,
		(Enum.Font :: any)[K.Font],
		Vector2.new(2000, 200)
	).X
	local x, y = TileLayout.place({
		w = size.X,
		h = size.Y,
		touch = UserInputService.TouchEnabled,
		centreX = centreX,
		yShare = C.ChallengeYShare,
		tilePx = px,
		wordPx = wordPx,
		wordWidth = wordWidth,
		pillPx = pillPx,
		gapPx = T.GapPx,
		offer = offer,
	})
	self.button.Size = UDim2.fromOffset(px, px)
	self.button.Position = UDim2.fromOffset(round(x), round(y))
	self.word.Size = UDim2.fromOffset(round(wordWidth + 12), wordPx + 4)
	HudParts.setTextSize(self.word, wordPx)
	HudParts.setTextSize(self.ends, pillTextPx, pillTextPx)
	local badgePx = if short then T.ShortBadgePx else T.BadgePx
	self.fresh.Size = UDim2.fromOffset(badgePx * 2, badgePx)
	self.alert.Size = UDim2.fromOffset(badgePx, badgePx)
	self:sizePill()
end

function EventButton.press(self: any)
	UISound.play("Click")
	UIAnim.bounce(self.button)
	local view = State.view()
	self.openedBoard = if type(view) == "table" then view.open or 0 else 0
	self.alert.Visible = false
	Menus.open(EventButton.MenuName)
end

--- Bounces the tile (a Candy chip landed on it).
function EventButton.bump(self: any)
	if self.shown then
		UIAnim.bounce(self.button)
	end
end

--- The tile's middle on the screen (where Candy flies), or nil while it is hidden.
function EventButton.target(self: any): Vector2?
	if not self.shown or not self.button.Visible then
		return nil
	end
	return self.button.AbsolutePosition + self.button.AbsoluteSize / 2
end

function EventButton.destroy(self: any)
	for _, c in self.connections do
		c:Disconnect()
	end
	self.button:Destroy()
end

return EventButton
