--!strict
-- JumpRail: a lively menu's jump buttons down its right side (the Shop's, the Free Reward's;
-- the lively-gui skill: "the tabs stand outside the panel's right edge"). One button per group
-- of the menu's one scrolling page: outside the panel's right edge when the screen has room
-- for them, else a column at the page's right (a phone). A press scrolls the page to its
-- group's top and staggers that group's pieces in again (its Stage ids); scrolling lights the
-- group in view; the lit button's icon rocks gently while the menu is open; LB and RB step
-- through the groups. Each button carries a red badge (the Shop's NEW, the Free Reward's "!"),
-- which the open pops in just after its button (Stage ids "Tab<n>" and "Tab<n>Badge"). The
-- menu sets each group's top on the page (rail.tops) as it lays the page out. Sizes in
-- Config.UI.Shop.Page (Rail*, JumpSeconds), shared by every menu with jump buttons.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local HudParts = require(script.Parent.HudParts)
local MenuFrame = require(script.Parent.MenuFrame)
local ShopParts = require(script.Parent.ShopParts)
local Stage = require(script.Parent.Stage)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local P = Config.UI.Shop.Page
local K = Config.UI.Kit
local PRIORITY = Enum.ContextActionPriority.High.Value + 20 -- like the menus' LB / RB
local span = ShopParts.span
local round = ShopParts.round

-- One jump group: its key, its words (Strings) and its icon (a Config.UI.Kit.Icons key).
export type Group = { key: string, text: string, icon: string }

export type Options = {
	frame: any, -- the menu's MenuFrame: the buttons go in its panel
	scroll: ScrollingFrame, -- the page they scroll
	groups: { Group }, -- top to bottom
	badge: string, -- the badges' words ("NEW", "!")
	badgeShare: number, -- a badge's width, of its height (a NEW pill is wider than a "!")
	action: string, -- the ContextActionService name for LB and RB while the menu is open
	root: (key: string) -> GuiObject?, -- a group's frame on the page (a jump replays its pieces)
}

type Jump = { key: string, button: TextButton, badge: Frame }

local JumpRail = {}
JumpRail.__index = JumpRail

--- Build the buttons (closed) into the frame's panel.
function JumpRail.new(opts: Options): any
	local self: any = setmetatable({}, JumpRail)
	self.frame = opts.frame
	self.scroll = opts.scroll
	self.groups = opts.groups
	self.action = opts.action
	self.rootOf = opts.root
	self.badgeShare = opts.badgeShare
	self.geo = nil :: MenuFrame.Geo?
	self.current = nil :: string? -- the lit button's group
	self.rock = nil :: UIAnim.Handle? -- the lit button's icon rocking
	self.tween = nil :: Tween? -- a jump's scroll while it runs
	self.laidWidth = nil :: number? -- the page's width at the menu's last layout while open
	-- Each group's top on the page in pixels, and a section's with its own place (the Shop's
	-- "Offer"): the menu's layout sets them.
	self.tops = {} :: { [string]: number }
	local rail = HudParts.frame(opts.frame.panel, "Jumps")
	rail.ZIndex = 4
	self.rail = rail
	self.jumps = {} :: { Jump }
	for _, group in opts.groups do
		local key = group.key
		local icon = if K.Icons[group.icon] and K.Icons[group.icon] ~= ""
			then group.icon
			else "Shop"
		local button = HudParts.tile(rail, group.text, function()
			UISound.play("Click")
			self:jump(key)
		end, "White", icon)
		button.Name = "Jump" .. key
		local badge = HudParts.pill(button, "Badge", HudParts.tone("Red"))
		badge.AnchorPoint = Vector2.new(0.5, 0.5)
		badge.ZIndex = 8
		badge.Visible = false
		local words = HudParts.text(badge, "Words", K.Text.Min, opts.badge)
		words.TextWrapped = false
		words.Size = UDim2.fromScale(1, 1)
		words.ZIndex = 9
		table.insert(self.jumps, { key = key, button = button, badge = badge })
	end
	-- Scrolling lights the group in view (not while a jump scrolls there itself).
	opts.scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		if self.tween == nil and self.frame:isOpen() then
			self:spy()
		end
	end)
	return self
end

--- Add the buttons and their badges to the menu's open (Stage ids "Tab<n>", "Tab<n>Badge").
function JumpRail.register(self: any, stage: Stage.Stage)
	for index, jump in self.jumps :: { Jump } do
		stage:add("Tab" .. index, jump.button)
		stage:add("Tab" .. index .. "Badge", jump.badge)
	end
end

function JumpRail.has(self: any, key: string): boolean
	for _, group in self.groups :: { Group } do
		if group.key == key then
			return true
		end
	end
	return false
end

--- The button of group `key`.
function JumpRail.button(self: any, key: string): TextButton?
	for _, jump in self.jumps :: { Jump } do
		if jump.key == key then
			return jump.button
		end
	end
	return nil
end

--- Every button, top to bottom (the gamepad's way back onto the menu).
function JumpRail.buttons(self: any): { TextButton }
	local list: { TextButton } = {}
	for _, jump in self.jumps :: { Jump } do
		table.insert(list, jump.button)
	end
	return list
end

--- Show or hide group `key`'s badge.
function JumpRail.setBadge(self: any, key: string, on: boolean)
	for _, jump in self.jumps :: { Jump } do
		if jump.key == key then
			jump.badge.Visible = on
		end
	end
end

--------------------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------------------

--- Whether the buttons fit outside a panel `panelW` wide (else a column in the page).
function JumpRail.outside(self: any, panelW: number): boolean
	local geo: MenuFrame.Geo? = self.geo
	local t = if geo then geo.t else 0
	local room = (self.frame.root.AbsoluteSize.X - panelW) / 2
	return room >= span(P.RailWidthPx, t) + 2 * P.RailOutsidePx
end

--- The page width a column of buttons inside the page takes.
function JumpRail.room(self: any, geo: MenuFrame.Geo?): number
	local t = if geo then geo.t elseif self.geo then self.geo.t else 0
	return span(P.RailWidthPx, t) + span(P.RailGapPx, t)
end

--- Place the buttons: outside the panel's right edge when the screen has room for them, else
--- a column at the right of the page. Returns the page width they leave.
function JumpRail.layout(self: any, geo: MenuFrame.Geo): number
	self.geo = geo
	local t = geo.t
	local frame = self.frame
	local panel: Frame = frame.panel
	local railW = span(P.RailWidthPx, t)
	local buttonH = span(P.RailButtonPx, t)
	local gap = span(P.RailGapPx, t)
	local textSize = math.max(K.Text.Min, span(P.RailTextPx, t))
	local n = #self.jumps
	local railH = n * buttonH + (n - 1) * gap
	-- Offsets, not absolute sizes: the panel may be mid pop-in (scaled) when this runs.
	local panelW = panel.Size.X.Offset
	local panelH = panel.Size.Y.Offset
	local outside = not geo.short and self:outside(panelW)
	local content: Frame = frame.content
	local contentTop = content.Position.Y.Offset
	local width = geo.content.X
	if outside then
		self.rail.Position =
			UDim2.fromOffset(panelW + P.RailOutsidePx, math.max(0, round((panelH - railH) / 2)))
	else
		local contentLeft = content.Position.X.Offset
		width = math.max(1, geo.content.X - railW - gap)
		self.rail.Position = UDim2.fromOffset(
			contentLeft + width + gap,
			contentTop + math.max(0, round((geo.content.Y - railH) / 2))
		)
	end
	self.rail.Size = UDim2.fromOffset(railW, railH)
	for index, jump in self.jumps :: { Jump } do
		jump.button.Position = UDim2.fromOffset(0, (index - 1) * (buttonH + gap))
		jump.button.Size = UDim2.fromOffset(railW, buttonH)
		HudParts.setButtonTextSize(jump.button, textSize)
		local badgeH = math.max(18, round(buttonH * 0.3))
		jump.badge.Size = UDim2.fromOffset(round(badgeH * self.badgeShare), badgeH)
		jump.badge.Position = UDim2.fromOffset(railW - 6, 6)
	end
	return width
end

--------------------------------------------------------------------------------------------
-- Jumping
--------------------------------------------------------------------------------------------

--- Light the button of group `key` (no scroll, no replay).
function JumpRail.light(self: any, key: string)
	if self.current == key then
		return
	end
	self.current = key
	for _, jump in self.jumps :: { Jump } do
		HudParts.setTone(jump.button, if jump.key == key then "Blue" else "White")
	end
	self:rockLit()
end

--- Light the group in view: the last one whose top is above a third of the way down.
function JumpRail.spy(self: any)
	local scroll: ScrollingFrame = self.scroll
	local mark = scroll.CanvasPosition.Y + scroll.AbsoluteSize.Y / 3
	local best, bestTop = nil, -1
	for _, group in self.groups :: { Group } do
		local top = self.tops[group.key]
		if top ~= nil and top <= mark and top > bestTop then
			best, bestTop = group.key, top
		end
	end
	if best then
		self:light(best)
	end
end

--- Scroll to `key`'s top (a group, or a section with its own top): at once, or over
--- Page.JumpSeconds.
function JumpRail.scrollTo(self: any, key: string, instant: boolean?)
	local top = self.tops[key]
	if top == nil then
		return
	end
	local scroll: ScrollingFrame = self.scroll
	local most = math.max(0, scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteSize.Y)
	local target = Vector2.new(0, math.clamp(top, 0, most))
	if self.tween then
		self.tween:Cancel()
		self.tween = nil
	end
	if instant or UIAnim.reduced() then
		scroll.CanvasPosition = target
		return
	end
	local tween = TweenService:Create(
		scroll,
		TweenInfo.new(P.JumpSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CanvasPosition = target }
	)
	self.tween = tween
	tween.Completed:Connect(function()
		if self.tween == tween then
			self.tween = nil
		end
	end)
	tween:Play()
end

--- Jump to group `key`: light its button, scroll to its top (at once with `instant`) and
--- stagger its pieces in again.
function JumpRail.jump(self: any, key: string, instant: boolean?)
	if not self:has(key) then
		return
	end
	local changed = self.current ~= key
	self:light(key)
	self:rockLit()
	local frame = self.frame
	if frame:isOpen() then
		self:scrollTo(key, instant)
	end
	-- A jump staggers its group's pieces in again (not during the open: it shows them).
	local stage = frame.stage
	local group = self.rootOf(key)
	if changed and group and stage and frame:isOpen() and stage:busy() ~= "play" then
		local ids = stage:idsUnder(group)
		if #ids > 0 then
			stage:replay(ids)
		end
	end
	if ShopParts.gamepad() then
		local button = self:button(key)
		if button then
			GuiService.SelectedObject = button
		end
	end
end

-- The lit button's icon rocks gently while the menu is open (the lively frame).
function JumpRail.rockLit(self: any)
	if self.rock then
		self.rock.stop()
		self.rock = nil
	end
	if not self.frame.stage or not self.frame:isOpen() then
		return
	end
	local L = Config.UI.Menu.Lively
	for _, jump in self.jumps :: { Jump } do
		local body = jump.button:FindFirstChild("Body")
		local icon = body and body:FindFirstChild("Icon")
		if jump.key == self.current and icon and icon:IsA("GuiObject") then
			self.rock = UIAnim.turn(icon, 0, L.TabRockDegrees, L.RockSeconds)
		end
	end
end

--- LB / RB: the previous / next group.
function JumpRail.step(self: any, dir: number)
	local groups: { Group } = self.groups
	local at = 1
	for index, group in groups do
		if group.key == self.current then
			at = index
		end
	end
	self:jump(groups[math.clamp(at + dir, 1, #groups)].key)
end

--- The menu opened: the first group lit (or the lit one rocking again), LB and RB bound.
function JumpRail.opened(self: any)
	if self.current == nil then
		self:jump(self.groups[1].key)
	else
		self:rockLit()
	end
	ContextActionService:BindActionAtPriority(
		self.action,
		function(_name: string, state: Enum.UserInputState, input: InputObject)
			if state == Enum.UserInputState.Begin and #self.frame.dialogs == 0 then
				self:step(if input.KeyCode == Enum.KeyCode.ButtonL1 then -1 else 1)
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		PRIORITY,
		Enum.KeyCode.ButtonL1,
		Enum.KeyCode.ButtonR1
	)
end

--- The menu closed: LB and RB let go, a jump's scroll and the rocking stop.
--- The menu laid its page out `width` pixels wide. When the width changed while open (a phone
--- turned, a window resized), every top moved: stay on the group being read, at its top.
function JumpRail.relaid(self: any, width: number)
	local before = self.laidWidth
	self.laidWidth = width
	if before ~= nil and before ~= width and self.current ~= nil then
		self:scrollTo(self.current, true)
	end
end

function JumpRail.closed(self: any)
	ContextActionService:UnbindAction(self.action)
	self.laidWidth = nil
	if self.tween then
		self.tween:Cancel()
		self.tween = nil
	end
	if self.rock then
		self.rock.stop()
		self.rock = nil
	end
end

return JumpRail
