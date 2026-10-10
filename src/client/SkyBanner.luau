--!strict
-- SkyBanner: the Sky Lucky Block's clock at the top of the lobby (economy v6, designer
-- 2026-10-10: "next sky lucky block in..."; SkyDropService). An Ink pill with the Sky block's
-- icon and "Next Sky Lucky Block in 12:34", in Roblox's top bar row: centred on the screen on a
-- computer or tablet, just right of the Settings gear on a phone (setAvoid; designer: no room
-- under the row there), and just under the row when the row has no room at all. Hidden before
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

--- The words now and their short form (a phone short of room), or nil when nothing shows.
function SkyBanner.words(self: any): (string?, string?)
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
	return W.SkyNext:format(time), W.SkyNextShort:format(time)
end

function SkyBanner.refresh(self: any)
	local words, short = nil, nil
	if self.wanted then
		words, short = self:words()
	end
	self.pill.Visible = words ~= nil
	if words == nil then
		self.laidFor = nil
		return
	end
	-- Laid out again only when its words or the screen change (the words tick once a second;
	-- this runs every frame while it shows).
	local camera = workspace.CurrentCamera
	local key = words .. tostring(camera and camera.ViewportSize)
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
	local centre = self.screen.AbsolutePosition.X + self.screen.AbsoluteSize.X / 2
	local size = U.TextPx
	local w, h, iconPx, textW = sized(size)
	local left = centre - w / 2
	local top = U.RowButtonTopPx + (U.RowButtonPx - h) / 2
	local placed = false
	if phone then
		-- A phone: in the row just right of the Settings gear (designer, 2026-10-10: no room
		-- for it under the row); short of room, its short words, then a little smaller.
		local edge = self:leftEdge()
		if edge then
			local room = origin.X + area.X - U.ClearPx - (edge + U.ClearPx)
			size = U.PhoneTextPx
			w, h, iconPx, textW = sized(size)
			if w > room and short then
				shown = short
				w, h, iconPx, textW = sized(size)
			end
			while w > room and size > U.PhoneMinTextPx do
				size -= 1
				w, h, iconPx, textW = sized(size)
			end
			if w <= room then
				left, top = edge + U.ClearPx, math.max(0, (area.Y - h) / 2)
				placed = true
			end
		end
	elseif not self:blocked(left - U.ClearPx, origin.Y + top, w + 2 * U.ClearPx, h) then
		-- A bigger screen: in the row, centred on the screen and on Roblox's buttons.
		placed = true
	end
	if not placed then
		-- Else just under the row, centred.
		shown = words :: string
		size = if phone then U.PhoneTextPx else U.TextPx
		w, h, iconPx, textW = sized(size)
		left, top = centre - w / 2, GuiService.TopbarInset.Height + U.TopGapPx
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

--- What the pill keeps clear of in the top row (the rank HUD, the Settings gear, the Players
--- list), and what a phone's pill sits just right of (the rank HUD and the gear; Progression).
function SkyBanner.setAvoid(self: any, objects: { GuiObject }, beside: { GuiObject })
	self.avoid = objects
	self.beside = beside
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
