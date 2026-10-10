--!strict
-- SkyBanner: the Sky Lucky Block's clock at the top of the lobby (economy v6, designer
-- 2026-10-10: "next sky lucky block in..."; SkyDropService). An Ink pill with the Sky block's
-- icon and "Next Sky Lucky Block in 12:34", in Roblox's top bar row centred on the screen, or
-- just under the row when the rank HUD, the Settings gear or the Players list leaves no room
-- there (setAvoid; a phone). Hidden before today's first finished match (designer: "just have
-- them finish a match then show the timer"), once today's has been earned, while one is
-- falling, and whenever the lobby is not quiet (Progression: setVisible). The server sends the clock ({ sky = view }) every Config.SkyBlock.TickSeconds;
-- between sends the time counts down here while the server says it runs (the player active).
--
-- It also tells the server the player is active: any input, at most every
-- Config.SkyBlock.ActivityPingSeconds ({ active = true } on the SkyDrop remote).
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Net = require(Shared:WaitForChild("Net"))
local HudParts = require(script.Parent.HudParts)

local C = Config.SkyBlock
local U = Config.UI.SkyBanner
local W = Strings.LuckyBlocks

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

--- The words now, or nil when nothing shows.
function SkyBanner.words(self: any): string?
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
	return W.SkyNext:format(clock(math.max(1, left)))
end

function SkyBanner.refresh(self: any)
	local words = if self.wanted then self:words() else nil
	self.pill.Visible = words ~= nil
	if words == nil then
		return
	end
	if self.text.Text ~= words then
		self.text.Text = words
	end
	local camera = workspace.CurrentCamera
	local phone = camera ~= nil and camera.ViewportSize.Y < Config.Multiplayer.Style.ShortHeight
	local size = if phone then U.PhoneTextPx else U.TextPx
	HudParts.setTextSize(self.text, size)
	local h = size + 2 * U.PadPx
	local iconPx = math.floor(h * U.IconShare)
	local textW = math.ceil(self.text.TextBounds.X) + 4
	local w = U.PadPx + iconPx + U.GapPx + textW + U.PadPx
	-- In the row, centred on the screen and on Roblox's buttons, unless that touches what
	-- the row already holds; then just under the row.
	local origin = self.gui.AbsolutePosition
	local centre = self.screen.AbsolutePosition.X + self.screen.AbsoluteSize.X / 2
	local left = centre - w / 2
	local top = U.RowButtonTopPx + (U.RowButtonPx - h) / 2
	if self:blocked(left - U.ClearPx, origin.Y + top, w + 2 * U.ClearPx, h) then
		top = GuiService.TopbarInset.Height + U.TopGapPx
	end
	self.pill.Position = UDim2.fromOffset(left - origin.X + w / 2, top)
	self.pill.Size = UDim2.fromOffset(w, h)
	self.icon.Size = UDim2.fromOffset(iconPx, iconPx)
	self.icon.Position = UDim2.fromOffset(U.PadPx, math.floor((h - iconPx) / 2))
	self.text.Position = UDim2.fromOffset(U.PadPx + iconPx + U.GapPx, 0)
	self.text.Size = UDim2.fromOffset(textW, h)
end

-- Whether anything in the avoid list shows over this rectangle (absolute pixels).
function SkyBanner.blocked(self: any, x: number, y: number, w: number, h: number): boolean
	for _, object in self.avoid :: { GuiObject } do
		local shown = object:IsDescendantOf(game)
		local at: Instance? = object
		while shown and at and not at:IsA("PlayerGui") do
			local hidden = (at:IsA("GuiObject") and not at.Visible)
				or (at:IsA("ScreenGui") and not at.Enabled)
			shown = not hidden
			at = at.Parent
		end
		if shown then
			local p, s = object.AbsolutePosition, object.AbsoluteSize
			if p.X < x + w and p.X + s.X > x and p.Y < y + h and p.Y + s.Y > y then
				return true
			end
		end
	end
	return false
end

--- What the pill keeps clear of in the top row: the rank HUD, the Settings gear, the Players
--- list (Progression).
function SkyBanner.setAvoid(self: any, objects: { GuiObject })
	self.avoid = objects
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
