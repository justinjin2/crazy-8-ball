--!strict
-- RankHud: your rank at the top left, in the free part of Roblox's top bar beside its menu,
-- chat and voice buttons (reference 02-rank-hud-nameplate): the badge, bigger than the pill and
-- over its left end, then a white pill with the rank's name ("Gold III") over the XP bar
-- ("520 / 1,000 XP" on the bar). Reyes has no top: its XP alone on a full rainbow bar that
-- shimmers. Unranked shows an empty bar out of Bronze I's width, which the first win fills.
--
-- It reads the local player's save from their attributes (RankXp and RatedMatches, which the
-- rank comes from, plus RankTier, RankDivision and RankIndex) and follows their changes: the
-- bar fills or drains and the numbers count; crossing a division, the bar runs to its end,
-- flashes, the badge swaps with a pop, and it carries on from the other end. Hidden until the
-- save is loaded (DataLoaded) and while you are in a match (setVisible, from Progression).
-- Pressing the badge or the pill opens the roadmap; a gamepad selects the badge.
--
-- It sits in its own ScreenGui with ScreenInsets.TopbarSafeInsets, which covers exactly the
-- free part of Roblox's top row (as MatchHUD's bar), laid out at Config sizes and scaled to fit.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Progression = Shared:WaitForChild("Progression")
local Ranks = require(Progression:WaitForChild("Ranks"))
local Format = require(Progression:WaitForChild("Format"))
local HudParts = require(script.Parent.HudParts)
local RankBadge = require(script.Parent.RankBadge)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local H = Config.UI.Progress.RankHud
local K = Config.UI.Kit
local S = Config.Multiplayer.Style
local Copy = Strings.Ranks
local color = HudParts.color

-- What the HUD shows: a division and the XP into it, out of `width` (nil: Reyes, no top).
type Shown = {
	index: number,
	tier: string,
	division: number,
	into: number,
	width: number?,
}

local RankHud = {}
RankHud.__index = RankHud

local WATCHED = { "RankXp", "RatedMatches", "RankTier", "RankDivision", "RankIndex" }

local function sameShown(a: Shown, b: Shown): boolean
	return a.index == b.index and a.into == b.into and a.width == b.width
end

-- The local player's rank from their save's attributes. The rank comes from RankXp and
-- RatedMatches (Ranks.fromXp), exactly as the server works it out.
local function readRank(player: Player?): Shown
	local xp = if player then player:GetAttribute("RankXp") else nil
	local matches = if player then player:GetAttribute("RatedMatches") else nil
	local rank = Ranks.fromXp(
		if type(xp) == "number" then xp else 0,
		type(matches) == "number" and matches > 0
	)
	if rank.index == 0 then
		-- Unranked: an empty bar out of Bronze I's width, which the first match fills from 0.
		return { index = 0, tier = rank.tier, division = 0, into = 0, width = Ranks.width(1) }
	end
	return {
		index = rank.index,
		tier = rank.tier,
		division = rank.division,
		into = rank.xpInDivision,
		width = rank.width,
	}
end

-- The fill's shading: a UIGradient multiplies the fill's colour, so its bottom is FillShade
-- divided by FillColor, channel by channel.
local SHADE = (function(): ColorSequence
	local function ratio(i: number): number
		local base = H.FillColor[i]
		return if base > 0 then math.min(1, H.FillShade[i] / base) else 1
	end
	local white = Color3.new(1, 1, 1)
	local bottom = Color3.new(ratio(1), ratio(2), ratio(3))
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, white),
		ColorSequenceKeypoint.new(0.5, white),
		ColorSequenceKeypoint.new(1, bottom),
	})
end)()

local function fraction(value: number, width: number?): number
	if width == nil then
		return 1
	end
	return if width > 0 then math.clamp(value / width, 0, 1) else 0
end

local function isTouch(): boolean
	return UserInputService:GetLastInputType() == Enum.UserInputType.Touch
end

--- Build the rank HUD. `screen` is the shared HUD ScreenGui (its size tells a phone from a
--- computer); the HUD itself lives in its own ScreenGui beside it. `onOpen` opens the roadmap.
function RankHud.new(screen: ScreenGui, onOpen: () -> ()): any
	local self: any = setmetatable({}, RankHud)
	self.screen = screen
	self.alive = true
	self.player = Players.LocalPlayer
	self.wanted = true -- Progression's say (not in a match)
	self.loaded = false -- the save is in (DataLoaded)
	self.showing = false
	self.token = 0 -- the latest animation; an older one stops at its next step
	self.pending = false
	self.connections = {}
	self.fillTween = nil
	self.colorTween = nil
	self.counter = nil
	self.lastTick = 0
	self.reyes = false
	self.shownIndex = nil -- the division whose badge and name are up
	self.shown = readRank(self.player)

	local gui = Instance.new("ScreenGui")
	gui.Name = "RankHud"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.TopbarSafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = screen.DisplayOrder
	gui.Parent = if self.player
		then self.player:FindFirstChildOfClass("PlayerGui") or screen.Parent
		else screen.Parent
	self.gui = gui

	local B, PW, PH = H.BadgePx, H.PillWidthPx, H.PillHeightPx
	local naturalWidth = B / 2 + PW
	self.naturalWidth, self.naturalHeight = naturalWidth, B
	-- The holder is laid out at the natural size and scaled to fit (layout); the body inside
	-- pops in and out about the badge's centre.
	local holder = HudParts.frame(gui, "Holder")
	holder.Size = UDim2.fromOffset(naturalWidth, B)
	self.fit = Instance.new("UIScale")
	self.fit.Parent = holder
	self.holder = holder
	local pivot = (B / 2) / naturalWidth
	local body = HudParts.frame(holder, "Body")
	body.AnchorPoint = Vector2.new(pivot, 0.5)
	body.Position = UDim2.fromScale(pivot, 0.5)
	body.Size = UDim2.fromScale(1, 1)
	body.Visible = false
	self.body = body

	-- The pill: a white kit card with round ends and a thick ink outline, under the badge.
	local pill = HudParts.card(body, "Pill", K.PillCornerPx)
	pill.Position = UDim2.fromOffset(B / 2, (B - PH) / 2)
	pill.Size = UDim2.fromOffset(PW, PH)
	self.pill = pill
	local left = B / 2 + H.PadPx
	local inner = PW - left - H.PadPx * 1.5
	local name = HudParts.text(pill, "RankName", H.NameTextPx, "")
	name.TextWrapped = false
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Position = UDim2.fromOffset(left, H.NameTopPx)
	name.Size = UDim2.fromOffset(inner, H.NameTextPx + 2)
	self.name = name
	-- The XP bar: a rounded track, the fill, a flash for crossing a division, and the numbers.
	local track = HudParts.frame(pill, "XpBar")
	track.BackgroundTransparency = 0
	track.BackgroundColor3 = color(H.TrackColor)
	track.Position = UDim2.fromOffset(left, PH - H.BarHeightPx - H.BarBottomPx)
	track.Size = UDim2.fromOffset(inner, H.BarHeightPx)
	HudParts.corner(track, K.PillCornerPx)
	local edge = Instance.new("UIStroke")
	edge.Color = HudParts.tone("Ink")
	edge.Thickness = H.BarStrokePx
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = track
	local fill = HudParts.frame(track, "Fill")
	fill.BackgroundTransparency = 0
	fill.BackgroundColor3 = color(H.FillColor)
	fill.Size = UDim2.fromScale(0, 1)
	HudParts.corner(fill, K.PillCornerPx)
	local shade = Instance.new("UIGradient")
	shade.Parent = fill
	self.fill, self.shade = fill, shade
	local flash = HudParts.frame(track, "Flash")
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.Size = UDim2.fromScale(1, 1)
	flash.ZIndex = 2
	HudParts.corner(flash, K.PillCornerPx)
	self.flashFrame = flash
	local numbers = HudParts.text(track, "Numbers", H.NumbersTextPx, "")
	numbers.TextWrapped = false
	numbers.AnchorPoint = Vector2.new(0.5, 0.5)
	numbers.Position = UDim2.fromScale(0.5, 0.5)
	numbers.Size = UDim2.new(1, -8, 1, 4)
	numbers.ZIndex = 3
	self.numbers = numbers
	-- The pill presses and hovers the badge too; only the badge is a gamepad stop.
	local pillButton = Instance.new("TextButton")
	pillButton.Name = "Press"
	pillButton.BackgroundTransparency = 1
	pillButton.Text = ""
	pillButton.AutoButtonColor = false
	pillButton.Selectable = false
	pillButton.Size = UDim2.fromScale(1, 1)
	pillButton.ZIndex = 5
	pillButton.Parent = pill

	-- The whole HUD grows under the mouse and squishes and bounces when pressed, badge and pill
	-- as one (designer, 2026-09-27), about the badge's centre.
	local bounce = Instance.new("UIScale")
	bounce.Name = "Bounce"
	bounce.Parent = body
	self.bounce = bounce
	self.bounceToken = 0
	self.hovers = {} :: { [string]: boolean }

	-- The badge, over the pill's left end. It sparkles on hover and press; the HUD does the
	-- growing.
	local badge = RankBadge.new(body, {
		size = B,
		interactive = true,
		onPress = function()
			self:bounceOnce()
			onOpen()
		end,
		name = "Badge",
		zIndex = 3,
		rays = false, -- they would cover the pill's words; Reyes' bar shimmers instead
		scale = false,
	})
	badge.root.Position = UDim2.fromOffset(0, 0)
	self.badge = badge
	local button = badge.button :: GuiButton
	-- Nothing is above or left of it on screen: a stick pushed that way stays on it.
	button.NextSelectionUp = button
	button.NextSelectionLeft = button

	local function connect(signal: RBXScriptSignal, handler: (...any) -> ())
		table.insert(self.connections, signal:Connect(handler))
	end
	-- Hovering anywhere on it (the pill, the badge) or a gamepad selection grows the whole HUD.
	local function hover(source: string, on: boolean)
		self.hovers[source] = on or nil
		local any = next(self.hovers) ~= nil
		badge:hover(any)
		self:settleScale()
	end
	connect(pillButton.MouseEnter, function()
		if not isTouch() then
			hover("pill", true)
		end
	end)
	connect(pillButton.MouseLeave, function()
		hover("pill", false)
	end)
	connect(button.MouseEnter, function()
		if not isTouch() then
			hover("badge", true)
		end
	end)
	connect(button.MouseLeave, function()
		hover("badge", false)
	end)
	connect(button.SelectionGained, function()
		hover("gamepad", true)
	end)
	connect(button.SelectionLost, function()
		hover("gamepad", false)
	end)
	connect(pillButton.Activated, function()
		badge:press()
	end)
	connect(gui:GetPropertyChangedSignal("AbsoluteSize"), function()
		self:layout()
	end)
	connect(screen:GetPropertyChangedSignal("AbsoluteSize"), function()
		self:layout()
	end)
	local player = self.player
	if player then
		for _, attribute in WATCHED do
			connect(player:GetAttributeChangedSignal(attribute), function()
				self:changed()
			end)
		end
		connect(player:GetAttributeChangedSignal("DataLoaded"), function()
			self.loaded = player:GetAttribute("DataLoaded") == true
			self:refreshVisible()
		end)
		self.loaded = player:GetAttribute("DataLoaded") == true
	end
	-- Reyes' full bar shimmers now and then while it shows.
	task.spawn(function()
		while self.alive do
			task.wait(H.ReyesShineEvery)
			if self.alive and self.showing and self.reyes then
				UIAnim.shine(self.fill)
			end
		end
	end)
	self:snap(self.shown)
	self:layout()
	self:refreshVisible()
	return self
end

-- Fit the HUD into the free part of the top row: its natural size (a phone), bigger on a
-- computer, smaller if the row is short of room; centred in the row's height, or hanging
-- just below the screen's top when bigger than the row.
function RankHud.layout(self: any)
	local area = self.gui.AbsoluteSize
	if area.X <= 0 then
		return
	end
	local screenHeight = self.screen.AbsoluteSize.Y
	local short = screenHeight > 0 and screenHeight < S.ShortHeight
	local scale = if short then 1 else H.ComputerScale
	local room = area.X - S.HeaderGap * 2
	if room > 0 then
		scale = math.min(scale, room / self.naturalWidth)
	end
	local rowHeight = if area.Y > 0 then area.Y else H.FallbackRowPx
	self.fit.Scale = scale
	self.holder.Position = UDim2.fromOffset(
		S.HeaderGap,
		math.max(H.TopMinPx, (rowHeight - self.naturalHeight * scale) / 2)
	)
end

-- Put a division's badge, name and bar colours up. `pop` bounces the badge.
function RankHud.showRank(self: any, rank: Shown, pop: boolean)
	self.shownIndex = rank.index
	self.badge:set(rank.tier, rank.division, pop)
	self.name.Text = Ranks.name({
		tier = rank.tier,
		division = rank.division,
		index = rank.index,
		xpInDivision = rank.into,
		width = rank.width,
	})
	local top = rank.index > 0 and rank.width == nil
	self.reyes = top
	if top then
		-- The house rainbow along the bar.
		local keys = {}
		for i, c in H.ReyesColors do
			local at = if #H.ReyesColors > 1 then (i - 1) / (#H.ReyesColors - 1) else 0
			table.insert(keys, ColorSequenceKeypoint.new(at, color(c)))
		end
		self.shade.Rotation = 0
		self.shade.Color = ColorSequence.new(keys)
		self.fill.BackgroundColor3 = Color3.new(1, 1, 1)
	else
		-- Gold, darkening to FillShade along its bottom, like a candy button's lip.
		self.shade.Rotation = 90
		self.shade.Color = SHADE
		self.fill.BackgroundColor3 = color(H.FillColor)
	end
end

function RankHud.showNumber(self: any, value: number, width: number?)
	self.numbers.Text = if width
		then Copy.XpOf:format(Format.xp(value), Format.xp(width))
		else Copy.XpOnly:format(Format.xp(value))
end

-- Stop whatever is animating (the fill, its colour, the count).
function RankHud.stop(self: any)
	self.token += 1
	if self.fillTween then
		self.fillTween:Cancel()
		self.fillTween = nil
	end
	if self.colorTween then
		self.colorTween:Cancel()
		self.colorTween = nil
	end
	if not self.reyes then
		self.fill.BackgroundColor3 = color(H.FillColor) -- a drain cut short leaves no red
	end
	if self.counter then
		local counter = self.counter
		self.counter = nil
		counter.stop()
	end
end

-- Show a rank at once, with no animation.
function RankHud.snap(self: any, rank: Shown)
	self:stop()
	self.shown = rank
	self:showRank(rank, false)
	self.fill.Size = UDim2.fromScale(fraction(rank.into, rank.width), 1)
	self:showNumber(rank.into, rank.width)
	self.flashFrame.BackgroundTransparency = 1
end

-- One leg: the fill from where it is to `to` XP (out of `width`), the numbers counting from
-- `from`, ticking as they go. `drain` turns the fill red on the way down.
function RankHud.leg(self: any, from: number, to: number, width: number?, drain: boolean)
	local seconds = H.FillSeconds
	local target = fraction(to, width)
	local fillTween = TweenService:Create(
		self.fill,
		TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(target, 1) }
	)
	self.fillTween = fillTween
	fillTween:Play()
	if not self.reyes then
		local base = color(H.FillColor)
		self.fill.BackgroundColor3 = if drain then color(H.DrainColor) else base
		if drain then
			local back = TweenService:Create(
				self.fill,
				TweenInfo.new(seconds * 1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ BackgroundColor3 = base }
			)
			self.colorTween = back
			back:Play()
		end
	end
	local pitch = Config.Audio.XpTickPitch
	self.counter = UIAnim.countUp(
		from,
		to,
		function(value: number)
			self:showNumber(value, width)
		end,
		seconds,
		function(value: number)
			local now = os.clock()
			if now - self.lastTick < H.TickEvery then
				return
			end
			self.lastTick = now
			local share = fraction(value, width)
			UISound.play("XpTick", pitch.From + (pitch.To - pitch.From) * share)
		end
	)
end

-- The bar crosses into another division: a flash (white going up, red going down).
function RankHud.flash(self: any, up: boolean)
	local flash = self.flashFrame
	flash.BackgroundColor3 = if up then Color3.new(1, 1, 1) else color(H.DrainColor)
	flash.BackgroundTransparency = 0
	TweenService:Create(
		flash,
		TweenInfo.new(H.FlashSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	):Play()
	if up then
		UISound.play("XpFull")
	end
end

-- Animate from what is up to `target`: fill or drain within the division; across a division
-- run to the end, flash, swap the badge with a pop, and carry on from the other end.
function RankHud.animate(self: any, target: Shown)
	local from: Shown = self.shown
	self:stop()
	local token = self.token
	self.shown = target
	if self.shownIndex ~= from.index then
		self:showRank(from, false) -- an interrupted swap: catch the badge up first
	end
	local function current(): boolean
		return self.alive and self.token == token
	end
	if target.index == from.index then
		self:leg(from.into, target.into, target.width, target.into < from.into)
		return
	end
	local up = target.index > from.index
	task.spawn(function()
		if from.index > 0 and from.width then
			self:leg(from.into, if up then from.width else 0, from.width, not up)
			task.wait(H.FillSeconds)
			if not current() then
				return
			end
		end
		self:flash(up)
		self:showRank(target, true)
		if target.index == 0 or target.width == nil then
			-- Unranked starts empty; Reyes is a full bar with its XP counting.
			self.fill.Size = UDim2.fromScale(fraction(0, target.width), 1)
			self:leg(0, target.into, target.width, false)
			return
		end
		local start = if up then 0 else target.width
		self.fill.Size = UDim2.fromScale(fraction(start, target.width), 1)
		self:leg(start, target.into, target.width, not up)
	end)
end

-- An attribute changed: coalesce the ones that arrive together, then follow the save.
function RankHud.changed(self: any)
	if self.pending then
		return
	end
	self.pending = true
	task.defer(function()
		self.pending = false
		if not self.alive then
			return
		end
		local target = readRank(self.player)
		if sameShown(target, self.shown) and self.shownIndex == target.index then
			return
		end
		if self.showing then
			self:animate(target)
		else
			self:snap(target)
		end
	end)
end

function RankHud.refreshVisible(self: any)
	local show = self.wanted and self.loaded
	if show == self.showing then
		return
	end
	self.showing = show
	if show then
		self:snap(readRank(self.player))
		UIAnim.popIn(self.body)
	else
		self:stop()
		table.clear(self.hovers)
		self.badge:hover(false)
		self:settleScale()
		UIAnim.popOut(self.body)
	end
end

--- Show or hide the HUD (Progression hides it while you are in a match); it pops in and out,
--- and stays hidden until the save is loaded. Cheap to call every frame.
function RankHud.setVisible(self: any, visible: boolean)
	if self.wanted == visible then
		return
	end
	self.wanted = visible
	self:refreshVisible()
end

-- The whole HUD's resting size: bigger while hovered.
function RankHud.restScale(self: any): number
	return if next(self.hovers) ~= nil then H.HoverScale else 1
end

-- Tween the whole HUD to its resting size (a hover starting or ending).
function RankHud.settleScale(self: any)
	self.bounceToken += 1
	TweenService:Create(
		self.bounce,
		TweenInfo.new(H.HoverSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = self:restScale() }
	):Play()
end

-- The press: the whole HUD squishes and bounces (Config.UI.Ranks.PressScales), then rests.
function RankHud.bounceOnce(self: any)
	self.bounceToken += 1
	local token = self.bounceToken
	local scales: { number } = Config.UI.Ranks.PressScales
	local seconds = Config.UI.Ranks.PressSeconds / #scales
	local index = 0
	local function nextStep()
		index += 1
		if token ~= self.bounceToken or not self.alive then
			return
		end
		local target = if index <= #scales then scales[index] * self:restScale() else nil
		if target == nil then
			return
		end
		local tween = TweenService:Create(
			self.bounce,
			TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Scale = target }
		)
		tween.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed then
				nextStep()
			end
		end)
		tween:Play()
	end
	nextStep()
end

--- The badge's button, for gamepad selection.
function RankHud.button(self: any): GuiButton
	return self.badge.button :: GuiButton
end

function RankHud.destroy(self: any)
	if not self.alive then
		return
	end
	self.alive = false
	self:stop()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	self.badge:destroy()
	self.gui:Destroy()
end

return RankHud
