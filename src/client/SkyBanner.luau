--!strict
-- SkyBanner: the Sky Lucky Block's clock at the top of the lobby (economy v6, designer
-- 2026-10-10: "next sky lucky block in..."; SkyDropService). An Ink pill with the Sky block's
-- icon and "Next Sky Lucky Block in 12:34", at the right end of Roblox's top bar row, left of
-- the Players list where it shows (designer, 2026-10-12: top right, so the tutorial's quest
-- line sits higher; it was centred, or right of the Settings gear on a phone). A phone short
-- of room shows "Sky Block in 12:34", then the icon and "12:34" alone (2026-10-13); only with
-- no room at all does it go just under the row at its right end (setAvoid). Hidden before
-- today's first finished match (designer: "just have them finish a match then show the
-- timer"), once today's has been earned, while one is falling, and whenever the lobby is not
-- quiet (Progression: setVisible). The server sends the clock ({ sky = view }) every
-- Config.SkyBlock.TickSeconds;
-- between sends the time counts down here while the server says it runs (the player active).
--
-- It also tells the server the player is active: any input, at most every
-- Config.SkyBlock.ActivityPingSeconds ({ active = true } on the SkyDrop remote).
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Net = require(Shared:WaitForChild("Net"))
local HudParts = require(script.Parent.HudParts)

local C = Config.SkyBlock
local U = Config.UI.SkyBanner
local W = Strings.LuckyBlocks
local BIG = Vector2.new(10000, 1000)

local SkyBanner = {}
SkyBanner.__index = SkyBanner

local function clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return ("%d:%02d"):format(s // 60, s % 60)
end

function SkyBanner.new(screen: ScreenGui): any
	local self: any = setmetatable({}, SkyBanner)
	self.view = nil :: any
	self.receivedAt = 0
	self.wanted = false
	self.screen = screen
	self.avoid = {} :: { GuiObject }
	self.beside = {} :: { GuiObject }
	self.below = {} :: { GuiObject }
	-- Its own ScreenGui over the free part of Roblox's top bar row (as RankHud and PlayerList),
	-- so its origin is the row's top-left on every device.
	local gui = Instance.new("ScreenGui")
	gui.Name = "SkyBanner"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.TopbarSafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = screen.DisplayOrder
	local player = Players.LocalPlayer
	gui.Parent = if player
		then player:FindFirstChildOfClass("PlayerGui") or screen.Parent
		else screen.Parent
	self.gui = gui
	local pill = HudParts.pill(gui, "SkyBanner", HudParts.tone("Ink"))
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.BackgroundTransparency = U.BackTransparency
	pill.Visible = false
	pill.ZIndex = 2
	self.pill = pill
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Image = Config.LuckyBlocks.Kinds.Sky.Icon
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = 3
	icon.Parent = pill
	self.icon = icon
	local text = HudParts.text(pill, "Words", U.TextPx, "")
	text.TextWrapped = false
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.AutoLocalize = false
	text.ZIndex = 3
	self.text = text

	Net.get("SkyDrop").OnClientEvent:Connect(function(payload: any)
		if type(payload) == "table" and type(payload.sky) == "table" then
			self.view = payload.sky
			self.receivedAt = os.clock()
			self:refresh()
		end
	end)
	-- Activity: any input, sent at most every ActivityPingSeconds.
	local lastSent = -math.huge
	local function active()
		local now = os.clock()
		if now - lastSent >= C.ActivityPingSeconds then
			lastSent = now
			Net.get("SkyDrop"):FireServer({ active = true })
		end
	end
	UserInputService.InputBegan:Connect(active)
	UserInputService.InputChanged:Connect(active)
	RunService.Heartbeat:Connect(function()
		if self.pill.Visible then
			self:refresh()
		end
	end)
	return self
end

--- The words now, their short form and the time alone (a phone short of room), or nil when
--- nothing shows.
function SkyBanner.words(self: any): (string?, string?, string?)
	local view = self.view
	if type(view) ~= "table" or view.pending == true or view.needsMatch == true then
		return nil
	elseif type(view.left) ~= "number" or view.left <= 0 then
		return nil
	end
	local left = view.left
	if view.running == true then
		left -= os.clock() - self.receivedAt
	end
	local time = clock(math.max(1, left))
	return W.SkyNext:format(time), W.SkyNextShort:format(time), W.SkyNextTime:format(time)
end

function SkyBanner.refresh(self: any)
	local words, short, timeOnly = nil, nil, nil
	if self.wanted then
		words, short, timeOnly = self:words()
	end
	self.pill.Visible = words ~= nil
	if words == nil then
		self.laidFor = nil
		return
	end
	-- Laid out again only when its words or the screen change (the words tick once a second;
	-- this runs every frame while it shows).
	local camera = workspace.CurrentCamera
	local key = words
		.. tostring(camera and camera.ViewportSize)
		.. tostring(self:bottomOver(-1e6, 2e6))
		.. self:avoidKey()
	if key == self.laidFor then
		return
	end
	self.laidFor = key
	local phone = camera ~= nil and camera.ViewportSize.Y < Config.Multiplayer.Style.ShortHeight
	local font = HudParts.measureFont(self.text)
	local shown = words :: string
	-- The pill's width, height, icon and words' width at a text size.
	local function sized(px: number): (number, number, number, number)
		local h = px + 2 * U.PadPx
		local iconPx = math.floor(h * U.IconShare)
		local textW = math.ceil(TextService:GetTextSize(shown, px, font, BIG).X) + 4
		return U.PadPx + iconPx + U.GapPx + textW + U.PadPx, h, iconPx, textW
	end
	local origin, area = self.gui.AbsolutePosition, self.gui.AbsoluteSize
	local size = if phone then U.PhoneTextPx else U.TextPx
	local w, h, iconPx, textW = sized(size)
	-- Its top in the row: centred in a phone's row, on Roblox's buttons on a bigger screen.
	local function rowTop(height: number): number
		return if phone
			then math.max(0, (area.Y - height) / 2)
			else U.RowButtonTopPx + (U.RowButtonPx - height) / 2
	end
	-- The row's right end (designer, 2026-10-12: "move the sky lucky block to the top right so
	-- then the 'now go win a match' can be higher"), left of what sits there (the Players
	-- list), never over the rank HUD or the Settings gear; short of room, its short words, then
	-- a little smaller.
	local right = self:rightEnd(origin.X + area.X - U.ClearPx, origin.Y + rowTop(h), w, h)
	local leftLimit = (self:leftEdge() or origin.X) + U.ClearPx
	if right - w < leftLimit and short then
		shown = short
		w, h, iconPx, textW = sized(size)
	end
	while right - w < leftLimit and size > U.PhoneMinTextPx do
		size -= 1
		w, h, iconPx, textW = sized(size)
	end
	-- A phone still short of room: the Sky block's icon and the time alone, in the row's top
	-- right (designer, 2026-10-13: "on phone it still isnt on the top right corner taking up a
	-- big chunk of the screen"; it went under the row with its long words).
	local tiny = phone and U.PhoneTimeOnly and timeOnly ~= nil
	if right - w < leftLimit and tiny then
		shown = timeOnly :: string
		size = U.PhoneTextPx
		w, h, iconPx, textW = sized(size)
		right = self:rightEnd(origin.X + area.X - U.ClearPx, origin.Y + rowTop(h), w, h)
	end
	local left, top = right - w, rowTop(h)
	if right - w < leftLimit then
		-- Else just under the row at its right end, under what hangs there too (a phone's
		-- with the time alone).
		shown = if tiny then timeOnly :: string else words :: string
		size = if phone then U.PhoneTextPx else U.TextPx
		w, h, iconPx, textW = sized(size)
		right = origin.X + area.X - U.ClearPx
		left, top = right - w, GuiService.TopbarInset.Height + U.TopGapPx
		local bottom = self:bottomOver(left, w)
		if bottom then
			top = math.max(top, bottom - origin.Y + U.TopGapPx)
		end
	end
	self.text.Text = shown
	HudParts.setTextSize(self.text, size)
	self.pill.Position = UDim2.fromOffset(left - origin.X + w / 2, top)
	self.pill.Size = UDim2.fromOffset(w, h)
	self.icon.Size = UDim2.fromOffset(iconPx, iconPx)
	self.icon.Position = UDim2.fromOffset(U.PadPx, math.floor((h - iconPx) / 2))
	self.text.Position = UDim2.fromOffset(U.PadPx + iconPx + U.GapPx, 0)
	self.text.Size = UDim2.fromOffset(textW, h)
end

-- Whether `object` shows (it and every holder visible, its ScreenGui on).
local function shows(object: GuiObject): boolean
	local shown = object:IsDescendantOf(game) and object.AbsoluteSize.X > 0
	local at: Instance? = object
	while shown and at and not at:IsA("PlayerGui") do
		local hidden = (at:IsA("GuiObject") and not at.Visible)
			or (at:IsA("ScreenGui") and not at.Enabled)
		shown = not hidden
		at = at.Parent
	end
	return shown
end

-- The right end (absolute pixels) of what a phone's pill sits beside (the rank HUD, the
-- Settings gear and its word), or nil when none shows.
function SkyBanner.leftEdge(self: any): number?
	local edge: number? = nil
	for _, object in self.beside :: { GuiObject } do
		local p, s = object.AbsolutePosition, object.AbsoluteSize
		if shows(object) then
			edge = math.max(edge or -math.huge, p.X + s.X)
		end
	end
	return edge
end

-- Whether anything in the avoid list shows over this rectangle (absolute pixels).
function SkyBanner.blocked(self: any, x: number, y: number, w: number, h: number): boolean
	for _, object in self.avoid :: { GuiObject } do
		if shows(object) then
			local p, s = object.AbsolutePosition, object.AbsoluteSize
			if p.X < x + w and p.X + s.X > x and p.Y < y + h and p.Y + s.Y > y then
				return true
			end
		end
	end
	return false
end

-- The pill's right end (absolute pixels) at most `right`, moved left of every shown avoid
-- object it would cover at that height (`y`, `h`) when `w` wide (the Players list).
function SkyBanner.rightEnd(self: any, right: number, y: number, w: number, h: number): number
	for _ = 1, #(self.avoid :: { GuiObject }) do
		local moved = false
		for _, object in self.avoid :: { GuiObject } do
			local p, s = object.AbsolutePosition, object.AbsoluteSize
			if
				shows(object)
				and p.Y < y + h
				and p.Y + s.Y > y
				and p.X < right
				and p.X + s.X > right - w
			then
				right = p.X - U.ClearPx
				moved = true
			end
		end
		if not moved then
			break
		end
	end
	return right
end

-- Where the shown avoid objects are, as words (the layout is redone when one moves or shows).
function SkyBanner.avoidKey(self: any): string
	local parts = {}
	for _, object in self.avoid :: { GuiObject } do
		if shows(object) then
			local p, s = object.AbsolutePosition, object.AbsoluteSize
			table.insert(parts, ("%d,%d,%d,%d"):format(p.X, p.Y, s.X, s.Y))
		end
	end
	return table.concat(parts, ";")
end

-- The lowest bottom edge (absolute pixels) of the shown `below` objects over the span `left`
-- to `left + w`, or nil when none is.
function SkyBanner.bottomOver(self: any, left: number, w: number): number?
	local bottom: number? = nil
	for _, object in self.below :: { GuiObject } do
		local p, s = object.AbsolutePosition, object.AbsoluteSize
		if shows(object) and p.X < left + w and p.X + s.X > left then
			bottom = math.max(bottom or -math.huge, p.Y + s.Y)
		end
	end
	return bottom
end

--- What the pill keeps clear of in the top row (the rank HUD, the Settings gear, the Players
--- list), what a phone's pill sits just right of (the rank HUD and the gear), and what it sits
--- under when it goes under the row (the rank HUD's goal line; Progression).
function SkyBanner.setAvoid(
	self: any,
	objects: { GuiObject },
	beside: { GuiObject },
	below: { GuiObject }?
)
	self.avoid = objects
	self.beside = beside
	self.below = below or {}
	self.laidFor = nil
	self:refresh()
end

--- Whether the lobby is quiet enough to show it (Progression).
function SkyBanner.setVisible(self: any, on: boolean)
	if self.wanted ~= on then
		self.wanted = on
		self:refresh()
	end
end

return SkyBanner
