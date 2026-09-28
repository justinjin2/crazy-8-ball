--!strict
-- TeleportScreen: the full screen shown from "Match found!" until the arena is ready
-- (designer, 2026-09-28: the teleport should feel quick). The same ScreenGui is handed to
-- Roblox (TeleportService:SetTeleportGui) so it stays up during the teleport's load, and the
-- arriving server's ReplicatedFirst script (src/first/Arrival) keeps it until the table is
-- there, so there is no flash of Roblox's default loading screen in between. Back to the
-- lobby uses it too. If the player is still here after Queue.TeleportGiveUpSeconds (the
-- teleport failed and the server said so, or Studio), it goes away.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local HudParts = require(script.Parent.HudParts)

local Q = Config.UI.Queue
local Copy = Strings.GlobalQueue
local TeleportScreen = {}
TeleportScreen.__index = TeleportScreen

TeleportScreen.GuiName = "TeleportScreen"

function TeleportScreen.new(): any
	local self: any = setmetatable({}, TeleportScreen)
	local gui = Instance.new("ScreenGui")
	gui.Name = TeleportScreen.GuiName
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = Q.TeleportZIndex
	gui.Enabled = false
	local back = Instance.new("Frame")
	back.Name = "Back"
	back.BorderSizePixel = 0
	back.BackgroundColor3 = HudParts.color(Q.TeleportColor)
	back.Size = UDim2.fromScale(1, 1)
	back.Parent = gui
	local title = HudParts.text(
		back,
		"Title",
		Q.TeleportTitlePx,
		Copy.FoundTitle,
		HudParts.color(Q.TeleportAccent)
	)
	title.TextWrapped = false
	title.AnchorPoint = Vector2.new(0.5, 1)
	title.Position = UDim2.fromScale(0.5, 0.5)
	title.Size = UDim2.new(0.9, 0, 0, Q.TeleportTitlePx + 8)
	local line = HudParts.text(back, "Line", Q.TeleportLinePx, Copy.Joining)
	line.TextWrapped = false
	line.AnchorPoint = Vector2.new(0.5, 0)
	line.Position = UDim2.new(0.5, 0, 0.5, 10)
	line.Size = UDim2.new(0.9, 0, 0, Q.TeleportLinePx + 8)
	self.gui, self.title, self.line = gui, title, line
	self.shownAt = nil
	local player = Players.LocalPlayer
	if player then
		gui.Parent = player:WaitForChild("PlayerGui")
	end
	return self
end

--- Show it: "Found" (a match, joining the arena) or "Home" (back to the lobby).
function TeleportScreen.show(self: any, kind: string)
	self.title.Visible = kind == "Found"
	self.line.Text = if kind == "Found" then Copy.Joining else Copy.ToLobby
	self.gui.Enabled = true
	self.shownAt = os.clock()
	pcall(function()
		TeleportService:SetTeleportGui(self.gui)
	end)
end

function TeleportScreen.hide(self: any)
	self.gui.Enabled = false
	self.shownAt = nil
end

function TeleportScreen.isShown(self: any): boolean
	return self.shownAt ~= nil
end

--- Every frame: the line breathes so the wait looks alive, and a teleport that never came
--- gives the screen back.
function TeleportScreen.update(self: any)
	local at = self.shownAt
	if not at then
		return
	end
	local t = os.clock() - at
	HudParts.setTextTransparency(self.line, 0.35 * (0.5 + 0.5 * math.sin(t * 4)))
	if t > Q.TeleportGiveUpSeconds then
		self:hide()
	end
end

return TeleportScreen
